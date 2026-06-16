# tests/test_flashcards.py
import pytest
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from features.flashcards import parse_flashcards


def test_parse_basic():
    raw = "Q: What is RAM?\nA: Random Access Memory\n\nQ: What is CPU?\nA: Central Processing Unit"
    cards = parse_flashcards(raw)
    assert len(cards) == 2
    assert cards[0]["question"] == "What is RAM?"
    assert cards[0]["answer"] == "Random Access Memory"


def test_parse_empty():
    assert parse_flashcards("") == []


def test_parse_malformed():
    """Should not crash on badly formatted output."""
    raw = "This is not a flashcard at all."
    result = parse_flashcards(raw)
    assert isinstance(result, list)


def test_parse_single():
    raw = "Q: Define deadlock.\nA: A state where processes wait indefinitely for each other."
    cards = parse_flashcards(raw)
    assert len(cards) == 1
