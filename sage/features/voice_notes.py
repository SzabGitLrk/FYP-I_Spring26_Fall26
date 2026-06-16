# features/voice_notes.py — Record audio → Moonshine STT → Phi-3.5 summary
import os
import numpy as np
import sounddevice as sd
import soundfile as sf
from rag.pipeline import run_rag
from utils.logger import get_logger
from utils.file_utils import safe_write, timestamp
from config import SAMPLE_RATE, CHANNELS, DTYPE, MOONSHINE_MODEL, TEMP_AUDIO
from config import NOTES_DIR, TRANSCRIPTS_DIR

logger = get_logger(__name__)

_moonshine = None
_whisper_processor = None
_whisper_model = None
# whisper-tiny ≈ 75 MB (vs whisper-small ≈ 967 MB). Tiny is more than
# accurate enough for short voice notes on a study laptop and avoids a
# nearly-1 GB download on first use. Override with the SAGE_WHISPER_MODEL
# env var if you want a larger model on a beefier machine.
_whisper_model_name = os.environ.get("SAGE_WHISPER_MODEL", "openai/whisper-tiny")


def _resample_audio(audio: np.ndarray, original_rate: int, target_rate: int) -> np.ndarray:
    if original_rate == target_rate:
        return audio
    duration = audio.shape[0] / original_rate
    target_len = int(duration * target_rate)
    return np.interp(
        np.linspace(0, len(audio) - 1, target_len),
        np.arange(len(audio)),
        audio
    ).astype(audio.dtype)


def _load_moonshine() -> bool:
    global _moonshine
    try:
        from moonshine_onnx import MoonshineOnnxModel  # type: ignore
        _moonshine = MoonshineOnnxModel(model_name=MOONSHINE_MODEL)
        logger.info(f"Moonshine loaded: {MOONSHINE_MODEL}")
        return True
    except Exception as e:
        logger.warning(f"Moonshine unavailable, will try Whisper fallback: {e}")
        _moonshine = None
        return False


def _load_whisper() -> bool:
    global _whisper_processor, _whisper_model
    try:
        from transformers import WhisperForConditionalGeneration, WhisperProcessor
        import torch

        _whisper_processor = WhisperProcessor.from_pretrained(_whisper_model_name)
        _whisper_model = WhisperForConditionalGeneration.from_pretrained(_whisper_model_name)
        _whisper_model.to("cpu")
        _whisper_model.eval()
        logger.info(f"Whisper fallback loaded: {_whisper_model_name}")
        return True
    except Exception as e:
        logger.error(f"Whisper fallback unavailable: {e}")
        _whisper_processor = None
        _whisper_model = None
        return False


def _ensure_transcriber() -> str:
    if _moonshine is not None:
        return "moonshine"
    if _whisper_model is not None and _whisper_processor is not None:
        return "whisper"

    if _load_moonshine():
        return "moonshine"
    if _load_whisper():
        return "whisper"

    raise RuntimeError(
        "No speech transcription engine available. ``moonshine_onnx`` is not installed and Whisper fallback could not initialize."
    )


def _transcribe_with_whisper(audio_path: str) -> str:
    if _whisper_model is None or _whisper_processor is None:
        raise RuntimeError("Whisper transcription model is not loaded.")

    import torch

    audio, sr = sf.read(audio_path)
    if audio.ndim > 1:
        audio = np.mean(audio, axis=1)
    if sr != SAMPLE_RATE:
        audio = _resample_audio(audio, sr, SAMPLE_RATE)
        sr = SAMPLE_RATE

    inputs = _whisper_processor(audio, sampling_rate=sr, return_tensors="pt")
    with torch.no_grad():
        generated_ids = _whisper_model.generate(
            inputs.input_features,
            max_new_tokens=225,
            num_beams=5,
        )
    transcript = _whisper_processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
    return transcript.strip()

# ── Recording state ────────────────────────────────────────────────────────
_recording = False
_audio_frames = []
_stream = None


def start_recording():
    """
    Begin capturing audio from the default microphone.
    Returns the sounddevice InputStream object.
    """
    global _recording, _audio_frames, _stream
    _recording = True
    _audio_frames = []

    def _callback(indata, frames, time, status):
        if status:
            logger.warning(f"Audio callback status: {status}")
        if _recording:
            _audio_frames.append(indata.copy())

    _stream = sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=CHANNELS,
        dtype=DTYPE,
        callback=_callback,
        blocksize=1024
    )
    _stream.start()
    logger.info("Recording started.")
    return _stream


def stop_recording() -> str:
    """
    Stop recording and transcribe with Moonshine.
    Returns the transcript as a string, or "" on failure.
    """
    global _recording, _stream
    _recording = False

    if _stream:
        _stream.stop()
        _stream.close()
        _stream = None

    if not _audio_frames:
        logger.warning("No audio frames captured.")
        return ""

    try:
        # Combine frames into one numpy array
        audio_data = np.concatenate(_audio_frames, axis=0).flatten()

        # Minimum length check (at least 0.5 seconds)
        if len(audio_data) < SAMPLE_RATE * 0.5:
            logger.warning("Recording too short to transcribe.")
            return ""

        # Save temporary WAV for Moonshine
        sf.write(TEMP_AUDIO, audio_data, SAMPLE_RATE)

        transcriber = _ensure_transcriber()
        if transcriber == "moonshine":
            # useful-moonshine-onnx exposes load_audio(audio) — single positional
            # arg. It accepts a file path (uses librosa internally, resampled to
            # 16 kHz) or a numpy array, and returns a [batch, samples] tensor.
            from moonshine_onnx import load_audio as _load_audio, load_tokenizer as _load_tokenizer  # type: ignore
            audio = _load_audio(TEMP_AUDIO)
            tokens = _moonshine.generate(audio)
            tokenizer = _load_tokenizer()
            transcript = tokenizer.decode_batch(tokens)[0]
        else:
            transcript = _transcribe_with_whisper(TEMP_AUDIO)

        logger.info(f"Transcribed {len(transcript)} chars.")
        return transcript.strip()

    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        return f"[Transcription error: {str(e)}]"
    finally:
        # Always clean up temp file
        if os.path.exists(TEMP_AUDIO):
            os.remove(TEMP_AUDIO)


def summarize_transcript(transcript: str, streaming_callback=None) -> str:
    """
    Summarize a voice note transcript using the RAG pipeline.
    Returns structured summary string.
    """
    if not transcript or "[error]" in transcript.lower():
        return "No valid transcript to summarize."

    ts = timestamp().replace("-", "").replace("_", "").replace(":", "")
    collection = f"voice_note_{ts}"

    task = """Summarize the key academic points from this voice note.
Structure the summary exactly as:

Main Topic:
[One sentence describing the main topic]

Key Points:
- [Point 1]
- [Point 2]
- [Point 3]
- [More if needed]

Important Terms:
- [Term]: [Definition]

Keep it concise and useful for studying."""

    return run_rag(
        text=transcript,
        task_prompt=task,
        collection_name=collection,
        num_predict=300,  # Voice summaries: 3 sections × ~100 tokens
        streaming_callback=streaming_callback
    )


def save_note(transcript: str, summary: str) -> str:
    """
    Save both transcript and summary as .txt files.
    Returns the path to the saved note file.
    """
    ts = timestamp()

    # Save raw transcript
    transcript_path = os.path.join(TRANSCRIPTS_DIR, f"transcript_{ts}.txt")
    safe_write(transcript_path, f"TRANSCRIPT — {ts}\n{'='*50}\n\n{transcript}")

    # Save note (transcript + summary together)
    note_path = os.path.join(NOTES_DIR, f"note_{ts}.txt")
    content = (
        f"VOICE NOTE — {ts}\n{'='*50}\n\n"
        f"ORIGINAL TRANSCRIPT:\n{transcript}\n\n"
        f"AI SUMMARY:\n{summary}"
    )
    safe_write(note_path, content)

    return note_path
