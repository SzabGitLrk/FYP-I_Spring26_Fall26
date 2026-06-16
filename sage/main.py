# main.py — SAGE entry point with splash screen
import sys
import os
import warnings

# Silence ChromaDB's anonymous telemetry. The bundled posthog client emits
# ``capture() takes 1 positional argument but 3 were given`` on every event
# in current Chroma builds — it is purely cosmetic noise that we never want
# during a demo. Must be set *before* chromadb is imported anywhere.
os.environ.setdefault("ANONYMIZED_TELEMETRY", "False")
os.environ.setdefault("CHROMA_TELEMETRY_ENABLED", "False")

# Force Hugging Face libraries into fully-offline mode. SAGE is designed to
# run with zero internet — Ollama is local, Whisper is local, and the
# sentence-transformers embedding model is pre-cached under
# ``~/.cache/huggingface/hub/`` by the setup scripts. Without these flags,
# every model load triggers a HEAD request to ``huggingface.co`` to check
# for updates, and if the machine is offline the request retries 5× with
# exponential backoff (~23 s of stderr spam per file) before falling back
# to the cache anyway. Setting these env vars makes the libraries skip the
# freshness check and go straight to the local cache.
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")

# The env vars above tell Chroma's *backend* not to send telemetry, but the
# pinned ``posthog`` library still has a broken ``capture()`` signature that
# Chroma calls unconditionally, printing ``Failed to send telemetry event …``
# to stderr on every operation. Monkey-patch the offending entrypoints to
# accept-and-ignore *anything* so the terminal stays clean.
try:
    import posthog  # type: ignore

    def _sage_noop_capture(*args, **kwargs):  # noqa: D401, ANN001
        return None

    posthog.capture = _sage_noop_capture
    # Some Chroma builds call ``Posthog.capture`` on an instance, not the
    # module-level function — patch the class method too if present.
    _PosthogClass = getattr(posthog, "Posthog", None)
    if _PosthogClass is not None:
        _PosthogClass.capture = _sage_noop_capture  # type: ignore[assignment]
except Exception:
    # posthog isn't installed → nothing to silence. Move on.
    pass

# Ensure the sage/ directory is on the Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Silence well-known third-party deprecation / version-pin chatter so the
# terminal stays clean for demos. These are cosmetic only — every flagged
# call still works correctly with the pinned versions in requirements.txt.
warnings.filterwarnings(
    "ignore",
    message=r"urllib3 .* or chardet .* doesn't match a supported version",
)

import customtkinter as ctk
from config import APPEARANCE_MODE, COLOR_THEME
from utils.logger import get_logger

logger = get_logger("main")

ctk.set_appearance_mode(APPEARANCE_MODE)
ctk.set_default_color_theme(COLOR_THEME)


def main():
    """SAGE startup sequence.

    1. Show ``SplashScreen`` (its own top-level ``ctk.CTk`` window) and
       run its ``mainloop()``. The splash performs the Ollama health
       check and pre-loads the embedding model on a background thread,
       then calls ``self.quit()`` to return control here.
    2. Read the success flag, fully destroy the splash window, then —
       on success — build and run the real ``SAGEApp`` window in a
       second, independent ``mainloop()``.

    Using two sequential top-level roots (rather than a hidden bootstrap
    root + a Toplevel splash) avoids the "application has been
    destroyed" race between CTk's global ``ScalingTracker`` /
    ``AppearanceModeTracker`` / ``ThemeManager`` and the font/theme
    initialization inside ``SAGEApp.__init__``.
    """
    from gui.splash import SplashScreen

    splash = SplashScreen(on_ready=None, on_error=None)
    splash.mainloop()  # blocks until splash calls self.quit()

    success = getattr(splash, "_success", False)
    error_msg = getattr(splash, "_error_msg", None)

    try:
        splash.destroy()
    except Exception:
        pass

    if not success:
        import tkinter.messagebox as mb
        mb.showerror(
            "SAGE — Startup Failed",
            f"SAGE could not start:\n\n{error_msg or 'Unknown error'}\n\n"
            f"Please fix the issue and restart."
        )
        return

    # Splash is fully torn down — build the real app window now.
    from gui.app import SAGEApp
    app = SAGEApp()
    app.mainloop()


if __name__ == "__main__":
    main()
