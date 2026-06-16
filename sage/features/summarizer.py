# features/summarizer.py — Load PPT/Word files and summarize via RAG
import os
from langchain_community.document_loaders import Docx2txtLoader
from langchain_community.document_loaders import UnstructuredPowerPointLoader
from rag.pipeline import run_rag
from utils.logger import get_logger
from utils.file_utils import safe_write, timestamp
from config import SUMMARIES_DIR, RETRIEVER_K_DOC

logger = get_logger(__name__)

SUMMARY_TASK = """Provide a structured academic summary with these sections:

DOCUMENT OVERVIEW:
(1-2 sentences: what is this document about?)

MAIN TOPICS COVERED:
(bullet list of the major topics)

KEY CONCEPTS & DEFINITIONS:
(list important terms and their meanings)

IMPORTANT POINTS TO REMEMBER:
(the most critical information)

CONCLUSION:
(what does the document conclude or recommend?)"""


def load_file(filepath: str) -> list:
    """
    Load a .docx or .pptx file into LangChain Document objects.
    Raises ValueError for unsupported file types.
    """
    if not os.path.exists(filepath):
        raise FileNotFoundError(f"File not found: {filepath}")

    ext = os.path.splitext(filepath)[1].lower()

    if ext == ".docx":
        logger.info(f"Loading Word document: {filepath}")
        loader = Docx2txtLoader(filepath)
    elif ext == ".pptx":
        logger.info(f"Loading PowerPoint: {filepath}")
        loader = UnstructuredPowerPointLoader(filepath, mode="elements")
    else:
        raise ValueError(
            f"Unsupported file type: '{ext}'\n"
            f"SAGE only supports .docx and .pptx files."
        )

    docs = loader.load()
    if not docs:
        raise ValueError("The file appears to be empty or unreadable.")

    logger.info(f"Loaded {len(docs)} document sections.")
    return docs


def summarize_file(filepath: str, progress_callback=None, streaming_callback=None) -> str:
    """
    Full RAG summarization pipeline for a PPT or Word file.

    Args:
        filepath:            Path to .docx or .pptx file
        progress_callback:   Optional function(float 0-1, str message)
                             called to update GUI progress bar
        streaming_callback:  Optional function(token: str) for real-time output

    Returns:
        str: Structured AI summary

    Raises:
        Exception: Propagated to GUI for display to user
    """
    def _progress(val, msg):
        if progress_callback:
            progress_callback(val, msg)

    filename = os.path.basename(filepath)
    ts = timestamp().replace("-", "").replace("_", "").replace(":", "")
    collection_name = f"doc_{ts}"

    # Step 1: Load file via the appropriate LangChain loader
    _progress(0.15, f"Loading {filename}...")
    docs = load_file(filepath)

    # Step 2: Flatten the loaded Document objects into a single text blob.
    # ``run_rag`` will handle chunking, embedding, retrieval and prompting
    # using the shared SAGE_PROMPT and Phi-3.5 LLM instance.
    _progress(0.35, "Preparing document content...")
    full_text = "\n\n".join(d.page_content for d in docs if d.page_content)
    if not full_text.strip():
        raise ValueError("The file contained no extractable text.")

    # Step 3-5: Delegate the full RAG pipeline (embed → store → retrieve →
    # invoke Phi-3.5) to the shared helper. ``RETRIEVER_K_DOC`` asks for a
    # few more chunks than the default since documents are typically longer
    # than voice transcripts.
    _progress(0.6, "Generating summary with Phi-3.5...")
    summary = run_rag(
        text=full_text,
        task_prompt=SUMMARY_TASK,
        collection_name=collection_name,
        k=RETRIEVER_K_DOC,
        num_predict=400,  # Summaries are bounded: 5 sections × ~80 tokens each
        streaming_callback=streaming_callback,  # Stream tokens to UI in real-time
    )

    # Step 6: Save to disk
    _progress(0.95, "Saving summary...")
    _save_summary(summary, filename, ts)

    _progress(1.0, "Done!")
    logger.info(f"Summary complete for: {filename}")
    return summary.strip()


def _save_summary(summary: str, filename: str, ts: str) -> str:
    """Save summary as a .txt file."""
    safe_name = filename.replace(" ", "_")
    for ext in [".pptx", ".docx", ".PPTX", ".DOCX"]:
        safe_name = safe_name.replace(ext, "")

    path = os.path.join(SUMMARIES_DIR, f"{safe_name}_summary_{ts}.txt")
    content = f"SUMMARY — {filename}\nGenerated: {ts}\n{'='*50}\n\n{summary}"
    safe_write(path, content)
    return path
