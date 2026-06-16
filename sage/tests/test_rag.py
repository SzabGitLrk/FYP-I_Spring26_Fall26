# tests/test_rag.py
# NOTE: These tests require Ollama to be running with phi3.5 pulled.
# They will be skipped automatically when Ollama is unavailable.
import pytest
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from rag.pipeline import run_rag
from utils.health_check import check_ollama


@pytest.fixture(scope="module")
def ollama_available():
    ok, _ = check_ollama()
    if not ok:
        pytest.skip("Ollama not available — skipping RAG integration tests")
    return True


def test_rag_returns_string(ollama_available):
    """RAG must return a non-empty string for valid input."""
    result = run_rag(
        text="Photosynthesis converts sunlight into glucose using chlorophyll in plant cells.",
        task_prompt="Summarize in one sentence.",
        collection_name="test_photosynthesis"
    )
    assert isinstance(result, str), "RAG must return a string"
    assert len(result) > 10, "Response is too short"


def test_rag_empty_input_raises(ollama_available):
    """RAG must raise ValueError for empty input."""
    with pytest.raises((ValueError, RuntimeError)):
        run_rag(text="", task_prompt="Summarize.", collection_name="test_empty")
