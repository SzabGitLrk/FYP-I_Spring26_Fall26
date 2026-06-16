# rag/pipeline.py — Shared RAG chain used by all three features
from langchain_community.llms import Ollama
from langchain.chains import RetrievalQA
from langchain.prompts import PromptTemplate
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.schema import Document
from rag.vectorstore import create_vectorstore_from_docs
from utils.logger import get_logger
from config import (
    OLLAMA_MODEL, OLLAMA_FALLBACK_MODELS, OLLAMA_TEMP, OLLAMA_CTX,
    OLLAMA_KEEP_ALIVE, OLLAMA_NUM_PREDICT_DEFAULT,
    CHUNK_SIZE, CHUNK_OVERLAP, RETRIEVER_K
)

logger = get_logger(__name__)

_llm = None
_current_model = None


def _create_llm(model_name: str):
    logger.info(f"Initializing Ollama LLM with model: {model_name}")
    return Ollama(
        model=model_name,
        temperature=OLLAMA_TEMP,
        num_ctx=OLLAMA_CTX,
        keep_alive=OLLAMA_KEEP_ALIVE,  # Keep model in RAM between calls
    )


def _get_llm():
    global _llm, _current_model
    if _llm is not None:
        return _llm

    models_to_try = [OLLAMA_MODEL] + [m for m in OLLAMA_FALLBACK_MODELS if m != OLLAMA_MODEL]
    last_error = None

    for model_name in models_to_try:
        try:
            _llm = _create_llm(model_name)
            _current_model = model_name
            return _llm
        except Exception as exc:
            logger.warning(f"Failed to initialize Ollama model '{model_name}': {exc}")
            last_error = exc

    raise RuntimeError(
        "Unable to initialize Ollama with any configured model. "
        f"Last error: {last_error}"
    )


# Text splitter shared across all features
splitter = RecursiveCharacterTextSplitter(
    chunk_size=CHUNK_SIZE,
    chunk_overlap=CHUNK_OVERLAP,
    separators=["\n\n", "\n", ".", " ", ""]
)

# Shared prompt template — all features inject their own task_prompt as {question}
SAGE_PROMPT = PromptTemplate(
    input_variables=["context", "question"],
    template="""You are SAGE, an AI academic assistant for university students.
Use ONLY the information provided in the context below.
Do not add information from your training data or make things up.

Context:
{context}

Task:
{question}

Response:"""
)


def run_rag(text: str, task_prompt: str, collection_name: str,
            k: int = RETRIEVER_K, num_predict: int | None = None,
            streaming_callback=None) -> str:
    """
    Core RAG function — used by all three features.

    Args:
        text:               Raw text to process (transcript, document content, etc.)
        task_prompt:        Instruction for Phi-3.5 (what to do with the content)
        collection_name:    ChromaDB collection name — unique per session/file
        k:                  Number of chunks to retrieve (default 4, use 5 for docs)
        num_predict:        Max output tokens (default None → use OLLAMA_NUM_PREDICT_DEFAULT)
        streaming_callback: Optional callable(token_text: str) for real-time output

    Returns:
        str: Phi-3.5's response, stripped of leading/trailing whitespace

    Raises:
        RuntimeError: If Ollama is not reachable or text is empty
    """
    if not text or not text.strip():
        raise ValueError("Input text is empty. Nothing to process.")

    logger.info(f"RAG start — collection: {collection_name}, k={k}, chars={len(text)}")

    try:
        # Step 1: Wrap in LangChain Document
        doc = Document(page_content=text, metadata={"source": collection_name})

        # Step 2: Split into chunks
        chunks = splitter.split_documents([doc])
        logger.info(f"Split into {len(chunks)} chunks")

        # Step 3: Embed + store in ChromaDB
        store = create_vectorstore_from_docs(chunks, collection_name)

        # Step 4: Create retriever. Cap ``k`` at the actual chunk count —
        # otherwise Chroma logs "Number of requested results N is greater
        # than number of elements in index M, updating n_results = M" for
        # every short input. The behaviour is identical, but we suppress
        # the warning by asking for what's actually available.
        effective_k = max(1, min(k, len(chunks)))
        retriever = store.as_retriever(search_kwargs={"k": effective_k})

        # Step 5: Build chain and invoke (with optional streaming)
        llm = _get_llm()
        # Apply per-call token budget if provided, else use default
        if num_predict is not None:
            llm.num_predict = num_predict
        else:
            llm.num_predict = OLLAMA_NUM_PREDICT_DEFAULT
        
        chain = RetrievalQA.from_chain_type(
            llm=llm,
            chain_type="stuff",
            retriever=retriever,
            chain_type_kwargs={"prompt": SAGE_PROMPT},
            return_source_documents=False
        )

        # For streaming: capture full response while feeding tokens to callback
        full_result = ""
        
        if streaming_callback is not None:
            # Streaming mode: custom callback for token streaming
            try:
                from langchain_core.callbacks.base import BaseCallbackHandler
            except ImportError:
                # Fallback if langchain_core not available
                class BaseCallbackHandler:
                    pass
            
            class CustomStreamCallback(BaseCallbackHandler):
                def __init__(self, callback):
                    super().__init__()
                    self.callback = callback
                
                def on_llm_new_token(self, token: str, **kwargs) -> None:
                    self.callback(token)
            
            stream_handler = CustomStreamCallback(streaming_callback)
            response = chain.invoke(
                {"query": task_prompt},
                config={"callbacks": [stream_handler]}
            )
            if isinstance(response, dict):
                full_result = response.get("result") or response.get("answer") or ""
            else:
                full_result = str(response)
        else:
            # Non-streaming mode (existing behavior)
            response = chain.invoke({"query": task_prompt})
            if isinstance(response, dict):
                full_result = response.get("result") or response.get("answer") or ""
            else:  # pragma: no cover - older LangChain shape
                full_result = str(response)
        
        logger.info(f"RAG complete — output length: {len(full_result)}")
        return full_result.strip()

    except Exception as e:
        logger.error(f"RAG failed: {e}")
        raise RuntimeError(f"AI processing failed: {str(e)}")
