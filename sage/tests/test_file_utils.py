# tests/test_file_utils.py
import pytest
import os
import tempfile
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from utils.file_utils import safe_write, safe_read, list_files


def test_write_and_read():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "test.txt")
        assert safe_write(path, "Hello SAGE")
        content = safe_read(path)
        assert content == "Hello SAGE"


def test_list_files():
    with tempfile.TemporaryDirectory() as d:
        for name in ["a.txt", "b.txt", "c.md"]:
            open(os.path.join(d, name), "w").close()
        files = list_files(d, ".txt")
        assert len(files) == 2


def test_read_missing_file():
    result = safe_read("/nonexistent/path/file.txt")
    assert result == ""
