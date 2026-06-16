# utils/file_utils.py — Safe read/write helpers used across features
import os
from datetime import datetime
from utils.logger import get_logger

logger = get_logger(__name__)


def safe_write(path: str, content: str) -> bool:
    """Write text to a file safely. Returns True on success."""
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        logger.info(f"Saved file: {path}")
        return True
    except Exception as e:
        logger.error(f"Failed to write {path}: {e}")
        return False


def safe_read(path: str) -> str:
    """Read text from a file safely. Returns empty string on failure."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        logger.error(f"Failed to read {path}: {e}")
        return ""


def list_files(directory: str, extension: str = ".txt") -> list:
    """
    List all files in a directory. Returns list of dicts:
    [{"name": "note_2026...", "path": "/full/path", "date": "2026-05-16 14:32"}]
    """
    results = []
    if not os.path.exists(directory):
        return results

    try:
        for fname in sorted(os.listdir(directory), reverse=True):
            if fname.endswith(extension):
                full_path = os.path.join(directory, fname)
                mod_time = os.path.getmtime(full_path)
                date_str = datetime.fromtimestamp(mod_time).strftime("%Y-%m-%d %H:%M")
                results.append({
                    "name": fname,
                    "path": full_path,
                    "date": date_str
                })
    except Exception as e:
        logger.error(f"Failed to list {directory}: {e}")

    return results


def timestamp() -> str:
    """Returns a filename-safe timestamp string."""
    return datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
