# rag/vectorstore.py — ChromaDB creation and loading helpers
from langchain_community.vectorstores import Chroma
from langchain.schema import Document
from rag.embeddings import get_embeddings
from utils.logger import get_logger
from config import CHROMA_DIR

logger = get_logger(__name__)


def create_vectorstore_from_docs(docs: list, collection_name: str) -> Chroma:
    """
    Embeds a list of LangChain Documents and stores them in ChromaDB.
    Each call creates/overwrites the named collection.
    """
    if not docs:
        raise ValueError("No documents provided to vectorstore.")

    # Sanitize collection name — ChromaDB only allows alphanumerics and underscores
    safe_name = "".join(c if c.isalnum() or c == "_" else "_" for c in collection_name)

    logger.info(f"Creating vectorstore: {safe_name} with {len(docs)} docs")
    embeddings = get_embeddings()

    store = Chroma.from_documents(
        documents=docs,
        embedding=embeddings,
        persist_directory=CHROMA_DIR,
        collection_name=safe_name
    )
    # Chroma >= 0.4.x auto-persists on write, so calling ``store.persist()``
    # is both unnecessary and emits a LangChainDeprecationWarning. We keep
    # the call only for older Chroma builds where it is still required.
    _persist = getattr(store, "persist", None)
    if callable(_persist):
        try:
            import chromadb  # type: ignore
            _ver = tuple(int(p) for p in chromadb.__version__.split(".")[:2])
            if _ver < (0, 4):
                _persist()
        except Exception:
            # If we can't determine the version, err on the side of silence.
            pass
    logger.info(f"Vectorstore saved: {safe_name}")
    return store


def load_vectorstore(collection_name: str) -> Chroma:
    """Load an existing ChromaDB collection from disk."""
    safe_name = "".join(c if c.isalnum() or c == "_" else "_" for c in collection_name)
    embeddings = get_embeddings()
    return Chroma(
        persist_directory=CHROMA_DIR,
        embedding_function=embeddings,
        collection_name=safe_name
    )
