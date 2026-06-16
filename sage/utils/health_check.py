# utils/health_check.py — Check Ollama is running BEFORE loading GUI
import requests
from utils.logger import get_logger
from config import OLLAMA_MODEL

logger = get_logger(__name__)


def check_ollama(model_name: str | None = None) -> tuple:
    """
    Returns (True, "") if Ollama is running and the model is available.
    Returns (False, error_message) otherwise.

    If ``model_name`` is None, the configured ``OLLAMA_MODEL`` from
    ``config.py`` (default ``phi3.5`` — Phi-3.5-mini 3.8B) is used.
    """
    if model_name is None:
        model_name = OLLAMA_MODEL
    try:
        # Check if Ollama server is running
        r = requests.get("http://localhost:11434", timeout=3)
        if r.status_code != 200:
            return False, "Ollama server is not responding. Run: ollama serve"
    except requests.ConnectionError:
        return False, (
            "Cannot connect to Ollama.\n\n"
            "Fix:\n"
            "1. Open a terminal\n"
            "2. Run: ollama serve\n"
            "3. Restart SAGE"
        )
    except requests.Timeout:
        return False, "Ollama is taking too long to respond. Try restarting it."

    try:
        # Check if the model is pulled
        r = requests.get("http://localhost:11434/api/tags", timeout=5)
        data = r.json()
        models = [m["name"] for m in data.get("models", [])]

        # phi3.5 may appear as "phi3.5", "phi3.5:latest", etc.
        model_found = any(model_name in m for m in models)

        if not model_found:
            return False, (
                f"Model '{model_name}' not found in Ollama.\n\n"
                f"Fix:\n"
                f"Run: ollama pull {model_name}"
            )
    except Exception as e:
        logger.warning(f"Could not verify model list: {e}")
        # Don't block startup if tag check fails — Ollama might still work

    logger.info("Ollama health check passed.")
    return True, ""
