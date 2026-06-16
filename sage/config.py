# config.py — Central configuration for SAGE
# Keep all settings here so you only change things in one place.

import os

# ── Paths ──────────────────────────────────────────────────────────────────
BASE_DIR     = os.path.dirname(os.path.abspath(__file__))
STORAGE_DIR  = os.path.join(BASE_DIR, "storage")
CHROMA_DIR   = os.path.join(BASE_DIR, "chroma_db")
LOGS_DIR     = os.path.join(BASE_DIR, "logs")
TEMP_AUDIO   = os.path.join(BASE_DIR, "temp_recording.wav")

NOTES_DIR        = os.path.join(STORAGE_DIR, "notes")
TRANSCRIPTS_DIR  = os.path.join(STORAGE_DIR, "transcripts")
SUMMARIES_DIR    = os.path.join(STORAGE_DIR, "summaries")
FLASHCARDS_DIR   = os.path.join(STORAGE_DIR, "flashcards")

# ── Audio Settings ─────────────────────────────────────────────────────────
SAMPLE_RATE = 16000   # Moonshine requires 16kHz
CHANNELS    = 1       # Mono only
DTYPE       = "float32"

# ── Moonshine STT ──────────────────────────────────────────────────────────
# Moonshine is the primary speech-to-text engine: ONNX-based, on-device,
# ~5-10× faster than equivalent Whisper models on CPU.
#   - moonshine/tiny   ~95 MB   (default — accurate enough for study notes,
#                                fast load, low memory footprint)
#   - moonshine/base   ~190 MB  (higher accuracy on noisy audio)
# Override via the SAGE_MOONSHINE_MODEL env var on stronger machines.
MOONSHINE_MODEL = os.environ.get("SAGE_MOONSHINE_MODEL", "moonshine/tiny")

# ── Ollama / LLM ───────────────────────────────────────────────────────────
# Default model is Phi-3.5-mini 3.8B (~2.2 GB quantized) — Microsoft's
# instruction-tuned small LM. Runs fully offline through Ollama and offers
# a strong accuracy/RAM trade-off on 8 GB machines. Override with the
# OLLAMA_MODEL env var (e.g. "tinyllama" for ~1 GB RAM systems, or
# "mistral:7b-instruct" on machines with more free RAM).
OLLAMA_URL       = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL     = os.environ.get("OLLAMA_MODEL", "phi3.5")
# Models tried in order if the configured OLLAMA_MODEL is unavailable.
OLLAMA_FALLBACK_MODELS = [
    "phi3.5:3.8b",          # explicit Phi-3.5-mini 3.8B tag
    "phi3.5",               # default Phi-3.5-mini tag
    "tinyllama",            # tiny ~640 MB fallback for low-RAM machines
    "mistral:7b-instruct-q4_0",
    "mistral:7b-instruct",
]
OLLAMA_TEMP      = 0.3
OLLAMA_CTX       = 2048  # Smaller context window to keep RAM use low on 8 GB systems
OLLAMA_KEEP_ALIVE = os.environ.get("OLLAMA_KEEP_ALIVE", "30m")  # Keep model in RAM between calls
OLLAMA_NUM_PREDICT_DEFAULT = 512  # Safe token ceiling (can be overridden per-feature)

# ── RAG Settings ───────────────────────────────────────────────────────────
CHUNK_SIZE       = 500
CHUNK_OVERLAP    = 50
RETRIEVER_K      = 4
RETRIEVER_K_DOC  = 5   # More context for longer documents

# ── Embedding Model ────────────────────────────────────────────────────────
EMBEDDING_MODEL  = "sentence-transformers/all-MiniLM-L6-v2"

# ── GUI ────────────────────────────────────────────────────────────────────
APP_TITLE        = "SAGE — AI Academic Companion"
APP_GEOMETRY     = "1100x750"
APP_MIN_SIZE     = (900, 650)
APPEARANCE_MODE  = "dark"
COLOR_THEME      = "blue"

# ── Ensure all directories exist ───────────────────────────────────────────
for _dir in [NOTES_DIR, TRANSCRIPTS_DIR, SUMMARIES_DIR, FLASHCARDS_DIR, LOGS_DIR, CHROMA_DIR]:
    os.makedirs(_dir, exist_ok=True)
