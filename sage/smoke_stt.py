"""smoke_stt.py — Headless Moonshine smoke test for SAGE.

Run with:  .\\sage_env\\Scripts\\python.exe smoke_stt.py

Verifies that:
  1. moonshine_onnx is importable
  2. The configured MOONSHINE_MODEL downloads + loads
  3. A short synthetic audio clip transcribes without error

This does NOT validate transcription quality (the input is silence/tone,
not speech) — it only proves the STT subsystem initialises end-to-end so
the Voice Notes tab will work the moment the user clicks Record.
"""
from __future__ import annotations

import sys
import time
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

sys.path.insert(0, str(Path(__file__).parent))

import numpy as np
import soundfile as sf

from config import MOONSHINE_MODEL, SAMPLE_RATE, TEMP_AUDIO


def main() -> int:
    print(f"[1/4] Importing moonshine_onnx ...")
    t0 = time.perf_counter()
    try:
        from moonshine_onnx import MoonshineOnnxModel  # type: ignore
    except Exception as e:
        print(f"   FAIL: {e}")
        return 1
    print(f"   OK ({time.perf_counter() - t0:.2f}s)")

    print(f"[2/4] Loading model '{MOONSHINE_MODEL}' (downloads on first run) ...")
    t0 = time.perf_counter()
    try:
        model = MoonshineOnnxModel(model_name=MOONSHINE_MODEL)
    except Exception as e:
        print(f"   FAIL: {e}")
        return 2
    print(f"   OK ({time.perf_counter() - t0:.2f}s)")

    print(f"[3/4] Writing 1.0s of synthetic audio to {TEMP_AUDIO} ...")
    sr = SAMPLE_RATE  # 16 kHz expected by Moonshine
    duration = 1.0
    t = np.linspace(0.0, duration, int(sr * duration), endpoint=False)
    # A faint 440 Hz tone with low amplitude — keeps the test deterministic
    # and lightweight; we are not checking content, only that inference runs.
    audio = (0.05 * np.sin(2.0 * np.pi * 440.0 * t)).astype(np.float32)
    Path(TEMP_AUDIO).parent.mkdir(parents=True, exist_ok=True)
    sf.write(TEMP_AUDIO, audio, sr, subtype="PCM_16")
    print(f"   OK")

    print(f"[4/4] Running inference ...")
    t0 = time.perf_counter()
    try:
        # moonshine_onnx accepts a file path or a numpy array; numpy is faster.
        tokens = model.generate(audio[np.newaxis, :])
        from moonshine_onnx import load_tokenizer  # type: ignore
        tokenizer = load_tokenizer()
        text = tokenizer.decode_batch(tokens)[0]
    except Exception as e:
        print(f"   FAIL: {e}")
        return 3
    elapsed = time.perf_counter() - t0
    print(f"   OK ({elapsed:.2f}s)")
    print(f"   Transcript (tone, expected to be empty/garbage): {text!r}")

    print("\nAll Moonshine STT smoke checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
