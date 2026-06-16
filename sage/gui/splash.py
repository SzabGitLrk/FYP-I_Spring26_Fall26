# gui/splash.py — Loading screen shown while models initialize
import customtkinter as ctk
import threading
from utils.health_check import check_ollama
from utils.logger import get_logger
from config import OLLAMA_MODEL

logger = get_logger(__name__)


class SplashScreen(ctk.CTk):
    """
    Loading window shown at startup.
    Checks Ollama, loads embedding model, then opens the main app.

    This is a top-level ``ctk.CTk`` (not a ``CTkToplevel``) so it owns its
    own Tcl interpreter. ``main.py`` runs the splash's ``mainloop()`` to
    completion, *then* builds the real ``SAGEApp`` window. This avoids
    the "application has been destroyed" race that happens when a hidden
    bootstrap root is torn down while CTk's global trackers still hold a
    reference to its interpreter.
    """
    def __init__(self, on_ready=None, on_error=None):
        # ``on_ready`` / ``on_error`` are accepted for backwards
        # compatibility but ignored — ``main.py`` now drives the
        # transition by reading ``self._success`` after ``mainloop()``
        # returns.
        super().__init__()
        self._success = False
        self._error_msg: str | None = None

        self.title("SAGE — Starting...")
        self.geometry("500x320")
        self.resizable(False, False)
        self._center()
        self._build_ui()

        # Start initialization in background
        threading.Thread(target=self._initialize, daemon=True).start()

    def _center(self):
        self.update_idletasks()
        w, h = 500, 320
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        self.geometry(f"{w}x{h}+{(sw - w) // 2}+{(sh - h) // 2}")

    def _build_ui(self):
        self.configure(fg_color="#0d1117")

        # Logo / title area
        ctk.CTkLabel(
            self, text="SAGE",
            font=ctk.CTkFont(family="Georgia", size=52, weight="bold"),
            text_color="#58a6ff"
        ).pack(pady=(40, 0))

        ctk.CTkLabel(
            self, text="Smart Academic Guide & Engine",
            font=ctk.CTkFont(size=14),
            text_color="#8b949e"
        ).pack(pady=(4, 8))

        ctk.CTkLabel(
            self, text="Voice Notes  ·  Flashcards  ·  Summarizer  ·  Dashboard",
            font=ctk.CTkFont(size=11),
            text_color="#484f58"
        ).pack(pady=(0, 24))

        self.status_label = ctk.CTkLabel(
            self, text="Starting up...",
            font=ctk.CTkFont(size=12),
            text_color="#8b949e"
        )
        self.status_label.pack()

        self.progress = ctk.CTkProgressBar(
            self, width=380, mode="indeterminate",
            progress_color="#58a6ff"
        )
        self.progress.pack(pady=15)
        self.progress.start()

    def _set_status(self, msg: str):
        """Thread-safe status update."""
        self.after(0, lambda: self.status_label.configure(text=msg))

    def _cancel_all_after(self):
        """Cancel every ``after`` callback scheduled on this splash.

        CustomTkinter's ``ScalingTracker`` schedules a recurring
        ``check_dpi_scaling`` job and CTk's titlebar setup schedules
        an ``update`` job on whichever Tk root it first sees. If we
        ``destroy()`` the splash while those are pending, Tk's
        background-error handler prints ``invalid command name
        "...check_dpi_scaling"`` / ``"...update"`` to stderr. Cancel
        them all before quitting the mainloop to keep output clean.
        """
        try:
            ids = self.tk.call("after", "info")
        except Exception:
            return
        try:
            id_list = self.tk.splitlist(ids)
        except Exception:
            id_list = (ids,) if ids else ()
        for after_id in id_list:
            try:
                self.after_cancel(after_id)
            except Exception:
                pass

    def _finish_ok(self):
        """Mark splash as successful and close it, returning control to main.py."""
        self._success = True
        try:
            self.progress.stop()
        except Exception:
            pass
        self._cancel_all_after()
        self.quit()  # ends mainloop; main.py will then destroy() us

    def _finish_error(self, msg: str):
        """Mark splash as failed and close it."""
        self._success = False
        self._error_msg = msg
        try:
            self.progress.stop()
        except Exception:
            pass
        self._cancel_all_after()
        self.quit()

    def _initialize(self):
        try:
            # Check Ollama — verify the configured LLM (default Phi-3.5-mini 3.8B)
            self._set_status(f"Checking Ollama ({OLLAMA_MODEL})...")
            ok, error_msg = check_ollama(OLLAMA_MODEL)
            if not ok:
                self.after(0, lambda: self._finish_error(error_msg))
                return

            # Pre-load embedding model (slow first time — ~5-10s)
            self._set_status("Loading embedding model (first run may take ~10s)...")
            from rag.embeddings import get_embeddings
            get_embeddings()

            self._set_status("✅  Ready!")
            self.after(600, self._finish_ok)

        except Exception as e:
            logger.error(f"Startup failed: {e}")
            self.after(0, lambda: self._finish_error(str(e)))
