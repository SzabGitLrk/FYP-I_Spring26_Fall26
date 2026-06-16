# features/flashcards.py — Generate and parse Q&A flashcards via RAG
import re
import os
from rag.pipeline import run_rag
from utils.logger import get_logger
from utils.file_utils import safe_write, timestamp
from config import FLASHCARDS_DIR

logger = get_logger(__name__)


def generate_flashcards(transcript: str, num_cards: int = 5) -> list:
    """
    Generate Q&A flashcards from a voice note transcript.

    Returns:
        List of dicts: [{"question": "...", "answer": "..."}, ...]
        Returns empty list if transcript is empty or RAG fails.
    """
    if not transcript or not transcript.strip():
        logger.warning("Empty transcript, cannot generate flashcards.")
        return []

    ts = timestamp().replace("-", "").replace("_", "").replace(":", "")
    collection = f"flashcards_{ts}"

    task = f"""Generate exactly {num_cards} flashcards from this academic content.

IMPORTANT: Follow this EXACT format for EVERY card. No extra text before or after.

Q: [A clear question about a concept, fact, or definition]
A: [A concise, accurate answer in 1-2 sentences]

Q: [Next question]
A: [Next answer]

Generate {num_cards} flashcards now:"""

    try:
        raw_output = run_rag(
            text=transcript,
            task_prompt=task,
            collection_name=collection,
            num_predict=600,  # ~5 cards × (20 tokens Q + 40 tokens A) with margin
        )
        logger.info(f"Raw flashcard output length: {len(raw_output)}")
        cards = parse_flashcards(raw_output)
        logger.info(f"Parsed {len(cards)} flashcards.")

        if cards:
            _save_flashcards(cards, ts)

        return cards

    except Exception as e:
        logger.error(f"Flashcard generation failed: {e}")
        return []


def parse_flashcards(raw: str) -> list:
    """
    Parse raw model output into a list of Q&A dicts.
    Handles variations in model output format.
    """
    cards = []
    if not raw:
        return cards

    # Primary parser: regex matching Q:/A: pairs across multiple lines
    pattern = r"Q:\s*(.+?)\s*A:\s*(.+?)(?=\nQ:|\Z)"
    matches = re.findall(pattern, raw, re.DOTALL)

    for question, answer in matches:
        q = question.strip().replace("\n", " ")
        a = answer.strip().replace("\n", " ")
        if q and a:
            cards.append({"question": q, "answer": a})

    # Fallback: line-by-line if regex fails
    if not cards:
        lines = raw.strip().split("\n")
        current_q = None
        for line in lines:
            line = line.strip()
            if line.startswith("Q:"):
                current_q = line[2:].strip()
            elif line.startswith("A:") and current_q:
                a = line[2:].strip()
                if current_q and a:
                    cards.append({"question": current_q, "answer": a})
                current_q = None

    return cards


def _save_flashcards(cards: list, ts: str) -> str:
    """Save flashcards to a timestamped .txt file."""
    path = os.path.join(FLASHCARDS_DIR, f"cards_{ts}.txt")
    lines = [f"FLASHCARDS — {ts}", "="*50, ""]
    for i, card in enumerate(cards, 1):
        lines.append(f"Card {i}")
        lines.append(f"Q: {card['question']}")
        lines.append(f"A: {card['answer']}")
        lines.append("")
    safe_write(path, "\n".join(lines))
    return path
