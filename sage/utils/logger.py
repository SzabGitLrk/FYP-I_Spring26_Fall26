# utils/logger.py — Rotating log file, does not clutter the terminal
import logging
import os
from logging.handlers import RotatingFileHandler
from config import LOGS_DIR

def get_logger(name: str) -> logging.Logger:
    """
    Returns a logger that writes to logs/sage.log (max 2MB, 3 backups).
    Call this at the top of every module:
        from utils.logger import get_logger
        logger = get_logger(__name__)
    """
    logger = logging.getLogger(name)

    if not logger.handlers:
        logger.setLevel(logging.DEBUG)

        log_path = os.path.join(LOGS_DIR, "sage.log")
        file_handler = RotatingFileHandler(
            log_path, maxBytes=2_000_000, backupCount=3, encoding="utf-8"
        )
        file_handler.setLevel(logging.DEBUG)

        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.WARNING)

        fmt = logging.Formatter(
            "[%(asctime)s] %(levelname)s %(name)s — %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
        file_handler.setFormatter(fmt)
        console_handler.setFormatter(fmt)

        logger.addHandler(file_handler)
        logger.addHandler(console_handler)

    return logger
