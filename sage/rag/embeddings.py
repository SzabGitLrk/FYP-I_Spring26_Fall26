# rag/embeddings.py — Singleton: load the embedding model exactly once
#
# Import strategy: use the dedicated ``langchain_huggingface`` package (the
# canonical home for ``HuggingFaceEmbeddings`` from LangChain 0.2.2 onward),
# falling back to ``langchain_community`` only on legacy installs that
# pre-date the split. The new package is pinned in requirements.txt so the
# preferred path is taken in normal SAGE installs and no
# LangChainDeprecationWarning is emitted at startup.
try:  # preferred path — langchain-huggingface is in requirements.txt
    from langchain_huggingface import HuggingFaceEmbeddings  # type: ignore
except Exception:  # pragma: no cover - exercised on older installs
    from langchain_community.embeddings import HuggingFaceEmbeddings  # type: ignore

from utils.logger import get_logger
from config import EMBEDDING_MODEL

logger = get_logger(__name__)
_embeddings = None


def get_embeddings() -> HuggingFaceEmbeddings:
    """
    Singleton — loads all-MiniLM-L6-v2 on first call, reuses after.
    Model is 22MB, runs on CPU, no internet needed after first download.
    """
    global _embeddings
    if _embeddings is None:
        logger.info(f"Loading embedding model: {EMBEDDING_MODEL}")
        _embeddings = HuggingFaceEmbeddings(
            model_name=EMBEDDING_MODEL,
            model_kwargs={"device": "cpu"},
            encode_kwargs={"normalize_embeddings": True}
        )
        logger.info("Embedding model loaded.")
    return _embeddings
