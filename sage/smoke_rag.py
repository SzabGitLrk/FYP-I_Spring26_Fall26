# smoke_rag.py — Headless end-to-end smoke test for the SAGE RAG pipeline.
#
# Runs OUTSIDE the GUI so we get fast feedback and a clean stack trace if
# anything is wrong. Verifies:
#   1. Ollama server is reachable
#   2. Configured OLLAMA_MODEL is present locally
#   3. rag.pipeline.run_rag() returns a non-empty response on a tiny passage
#
# Exit code 0 on success, non-zero on any failure.

from __future__ import annotations

import sys
import time
import json
import urllib.request
import urllib.error

from config import OLLAMA_URL, OLLAMA_MODEL, OLLAMA_CTX


SAMPLE_TEXT = (
    "Photosynthesis is the process by which green plants and some other "
    "organisms use sunlight to synthesize foods from carbon dioxide and "
    "water. Photosynthesis in plants generally involves the green pigment "
    "chlorophyll and generates oxygen as a by-product."
)

TASK_PROMPT = (
    "Write ONE short sentence (max 20 words) summarising the passage. "
    "Do not add any information not present in the context."
)


def _section(title: str) -> None:
    print(f"\n{'=' * 60}\n{title}\n{'=' * 60}")


def check_ollama_server() -> dict:
    _section("1. Ollama server health")
    url = f"{OLLAMA_URL.rstrip('/')}/api/tags"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"  [FAIL] Cannot reach {url}: {exc}")
        sys.exit(2)

    models = [m["name"] for m in data.get("models", [])]
    print(f"  [OK]   {url} -> 200")
    print(f"  Installed models: {models}")
    return {"models": models}


def check_model_present(models: list[str]) -> None:
    _section(f"2. Configured model present? ({OLLAMA_MODEL})")
    # Ollama lists names like "tinyllama:latest" — match by prefix on the bare name.
    target = OLLAMA_MODEL.split(":")[0]
    matched = [m for m in models if m.split(":")[0] == target]
    if not matched:
        print(f"  [FAIL] Model '{OLLAMA_MODEL}' not in installed list.")
        print(f"         Run:  ollama pull {OLLAMA_MODEL}")
        sys.exit(3)
    print(f"  [OK]   matched: {matched}")


def run_rag_smoke() -> None:
    _section(f"3. RAG pipeline smoke test (model={OLLAMA_MODEL}, ctx={OLLAMA_CTX})")
    # Import here so any failure in step 1/2 is reported before the heavy
    # imports (sentence-transformers, chroma) kick in.
    from rag.pipeline import run_rag

    collection = f"smoke_{int(time.time())}"
    print(f"  collection: {collection}")
    print(f"  task:       {TASK_PROMPT}")
    print("  running... (this loads the embedding model on first call — be patient)")

    t0 = time.perf_counter()
    try:
        result = run_rag(SAMPLE_TEXT, TASK_PROMPT, collection, k=2)
    except Exception as exc:
        print(f"\n  [FAIL] run_rag raised: {type(exc).__name__}: {exc}")
        sys.exit(4)
    elapsed = time.perf_counter() - t0

    if not result or not result.strip():
        print(f"  [FAIL] Empty response after {elapsed:.1f}s")
        sys.exit(5)

    print(f"\n  [OK]   elapsed: {elapsed:.1f}s")
    print(f"  response ({len(result)} chars):")
    print("  " + "-" * 56)
    for line in result.splitlines() or [result]:
        print(f"  | {line}")
    print("  " + "-" * 56)


def main() -> int:
    print(f"OLLAMA_URL   = {OLLAMA_URL}")
    print(f"OLLAMA_MODEL = {OLLAMA_MODEL}")
    print(f"OLLAMA_CTX   = {OLLAMA_CTX}")

    info = check_ollama_server()
    check_model_present(info["models"])
    run_rag_smoke()

    _section("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
