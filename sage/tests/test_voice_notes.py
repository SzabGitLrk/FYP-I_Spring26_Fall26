import os
import sys
import pytest
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from features.voice_notes import save_note, summarize_transcript


def test_summarize_transcript_mock_run_rag(monkeypatch):
    expected_summary = "This is a mocked summary."

    def fake_run_rag(text, task_prompt, collection_name):
        assert "voice note" in task_prompt.lower()
        assert "mock" not in text.lower()
        return expected_summary

    monkeypatch.setattr("features.voice_notes.run_rag", fake_run_rag)
    result = summarize_transcript("This is a test transcript for voice notes.")
    assert result == expected_summary


def test_summarize_transcript_empty():
    assert summarize_transcript("") == "No valid transcript to summarize."


def test_save_note_writes_files(tmp_path, monkeypatch):
    transcripts_dir = tmp_path / "transcripts"
    notes_dir = tmp_path / "notes"
    transcripts_dir.mkdir()
    notes_dir.mkdir()

    monkeypatch.setattr("features.voice_notes.TRANSCRIPTS_DIR", str(transcripts_dir))
    monkeypatch.setattr("features.voice_notes.NOTES_DIR", str(notes_dir))

    transcript = "Test audio transcript."
    summary = "Test summary output."
    note_path = save_note(transcript, summary)

    assert os.path.exists(note_path)
    assert note_path.endswith(".txt")
    with open(note_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Test audio transcript." in content
    assert "Test summary output." in content
