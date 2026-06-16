# gui/voice_tab.py — Voice Notes tab with professional layout
import customtkinter as ctk
import threading
from utils.logger import get_logger

logger = get_logger(__name__)


class VoiceTab(ctk.CTkFrame):
    def __init__(self, parent, on_flashcard_request):
        super().__init__(parent, fg_color="transparent")
        self.on_flashcard_request = on_flashcard_request
        self._stream = None
        self.transcript = ""
        self.summary = ""
        self._build_ui()

    def _build_ui(self):
        # ── Page Title ─────────────────────────────────────────────────────
        title_frame = ctk.CTkFrame(self, fg_color="transparent")
        title_frame.pack(fill="x", padx=24, pady=(20, 0))

        ctk.CTkLabel(
            title_frame, text="🎙  Voice Notes",
            font=ctk.CTkFont(family="Georgia", size=26, weight="bold"),
            text_color="#c9d1d9"
        ).pack(side="left")

        ctk.CTkLabel(
            title_frame,
            text="Record → Transcribe → Summarize → Flashcards",
            font=ctk.CTkFont(size=12), text_color="#484f58"
        ).pack(side="left", padx=16)

        # ── Recording Controls ─────────────────────────────────────────────
        ctrl = ctk.CTkFrame(self, fg_color="#161b22", corner_radius=10)
        ctrl.pack(fill="x", padx=24, pady=16)

        inner = ctk.CTkFrame(ctrl, fg_color="transparent")
        inner.pack(padx=20, pady=16)

        self.record_btn = ctk.CTkButton(
            inner, text="⏺  Start Recording",
            width=200, height=44,
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color="#da3633", hover_color="#b91c1c",
            corner_radius=8,
            command=self._start_recording
        )
        self.record_btn.grid(row=0, column=0, padx=10)

        self.stop_btn = ctk.CTkButton(
            inner, text="⏹  Stop",
            width=140, height=44,
            font=ctk.CTkFont(size=14),
            fg_color="#21262d", hover_color="#30363d",
            state="disabled",
            corner_radius=8,
            command=self._stop_recording
        )
        self.stop_btn.grid(row=0, column=1, padx=10)

        self.status_label = ctk.CTkLabel(
            ctrl, text="Press Start Recording to begin",
            font=ctk.CTkFont(size=12), text_color="#8b949e"
        )
        self.status_label.pack(pady=(0, 14))

        # ── Output Area — Two Columns ──────────────────────────────────────
        split = ctk.CTkFrame(self, fg_color="transparent")
        split.pack(fill="both", expand=True, padx=24, pady=(0, 16))
        split.columnconfigure(0, weight=1)
        split.columnconfigure(1, weight=1)
        split.rowconfigure(1, weight=1)

        # Left: Transcript
        ctk.CTkLabel(
            split, text="Transcript",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#8b949e"
        ).grid(row=0, column=0, sticky="w", pady=(0, 4))

        self.transcript_box = ctk.CTkTextbox(
            split,
            font=ctk.CTkFont(family="Courier New", size=12),
            fg_color="#161b22", text_color="#c9d1d9",
            corner_radius=8, border_width=1, border_color="#30363d",
            wrap="word"
        )
        self.transcript_box.grid(row=1, column=0, sticky="nsew", padx=(0, 8))

        # Right: Summary
        ctk.CTkLabel(
            split, text="AI Summary",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#8b949e"
        ).grid(row=0, column=1, sticky="w", pady=(0, 4))

        self.summary_box = ctk.CTkTextbox(
            split,
            font=ctk.CTkFont(size=12),
            fg_color="#161b22", text_color="#c9d1d9",
            corner_radius=8, border_width=1, border_color="#30363d",
            wrap="word"
        )
        self.summary_box.grid(row=1, column=1, sticky="nsew", padx=(8, 0))

        # ── Action Buttons ─────────────────────────────────────────────────
        act = ctk.CTkFrame(self, fg_color="transparent")
        act.pack(pady=(0, 8))

        self.save_btn = ctk.CTkButton(
            act, text="💾  Save Note",
            width=160, height=38,
            fg_color="#238636", hover_color="#2ea043",
            state="disabled", corner_radius=8,
            command=self._save_note
        )
        self.save_btn.pack(side="left", padx=8)

        self.flashcard_btn = ctk.CTkButton(
            act, text="🃏  Generate Flashcards",
            width=200, height=38,
            fg_color="#1f6feb", hover_color="#388bfd",
            state="disabled", corner_radius=8,
            command=self._make_flashcards
        )
        self.flashcard_btn.pack(side="left", padx=8)

        self.clear_btn = ctk.CTkButton(
            act, text="🗑  Clear",
            width=100, height=38,
            fg_color="#21262d", hover_color="#30363d",
            corner_radius=8,
            command=self._clear
        )
        self.clear_btn.pack(side="left", padx=8)

    # ── Event Handlers ─────────────────────────────────────────────────────
    def _start_recording(self):
        from features.voice_notes import start_recording
        try:
            self._stream = start_recording()
            self.record_btn.configure(state="disabled")
            self.stop_btn.configure(state="normal")
            self._set_status("🔴  Recording... Press Stop when done", "#f85149")
            self.transcript_box.delete("1.0", "end")
            self.summary_box.delete("1.0", "end")
            self.save_btn.configure(state="disabled")
            self.flashcard_btn.configure(state="disabled")
        except Exception as e:
            self._show_error(f"Could not start recording:\n{e}")

    def _stop_recording(self):
        self.stop_btn.configure(state="disabled")
        self._set_status("⏳  Transcribing with Moonshine...", "#d29922")

        def _process():
            try:
                from features.voice_notes import stop_recording, summarize_transcript

                self.transcript = stop_recording()
                if not self.transcript:
                    self.after(0, lambda: self._set_status(
                        "⚠  No audio captured. Try again.", "#f85149"
                    ))
                    self.after(0, lambda: self.record_btn.configure(state="normal"))
                    return

                self.after(0, lambda: self.transcript_box.insert("end", self.transcript))
                self.after(0, lambda: self._set_status(
                    "⏳  Summarizing with Phi-3.5...", "#d29922"
                ))

                # Clear the summary box for streaming
                self.after(0, lambda: self.summary_box.delete("1.0", "end"))

                # Define the streaming callback
                def stream_summary(token: str):
                    self.after(0, lambda: self.summary_box.insert("end", token))
                    self.after(0, lambda: self.summary_box.see("end"))

                self.summary = summarize_transcript(
                    self.transcript,
                    streaming_callback=stream_summary
                )

                self.after(0, lambda: self._set_status("✅  Complete!", "#3fb950"))
                self.after(0, lambda: self.record_btn.configure(state="normal"))
                self.after(0, lambda: self.save_btn.configure(state="normal"))
                self.after(0, lambda: self.flashcard_btn.configure(state="normal"))

            except Exception as e:
                logger.error(f"Processing failed: {e}")
                self.after(0, lambda: self._show_error(f"Processing failed:\n{e}"))
                self.after(0, lambda: self.record_btn.configure(state="normal"))

        threading.Thread(target=_process, daemon=True).start()

    def _save_note(self):
        try:
            from features.voice_notes import save_note
            path = save_note(self.transcript, self.summary)
            self._set_status(f"✅  Saved: {path}", "#3fb950")
        except Exception as e:
            self._show_error(f"Save failed:\n{e}")

    def _make_flashcards(self):
        self._set_status("⏳  Generating flashcards...", "#d29922")
        self.flashcard_btn.configure(state="disabled")

        def _generate():
            try:
                from features.flashcards import generate_flashcards
                cards = generate_flashcards(self.transcript, num_cards=5)
                count = len(cards)
                self.after(0, lambda: self._set_status(
                    f"✅  {count} flashcards created!", "#3fb950"
                ))
                self.after(0, lambda: self.flashcard_btn.configure(state="normal"))
                self.after(0, lambda: self.on_flashcard_request(cards))
            except Exception as e:
                logger.error(f"Flashcard generation failed: {e}")
                self.after(0, lambda: self._show_error(
                    f"Flashcard generation failed:\n{e}"
                ))
                self.after(0, lambda: self.flashcard_btn.configure(state="normal"))

        threading.Thread(target=_generate, daemon=True).start()

    def _clear(self):
        self.transcript = ""
        self.summary = ""
        self.transcript_box.delete("1.0", "end")
        self.summary_box.delete("1.0", "end")
        self.save_btn.configure(state="disabled")
        self.flashcard_btn.configure(state="disabled")
        self._set_status("Cleared.", "#8b949e")

    def _set_status(self, msg, color="#8b949e"):
        self.after(0, lambda: self.status_label.configure(
            text=msg, text_color=color
        ))

    def _show_error(self, msg):
        from tkinter import messagebox
        messagebox.showerror("SAGE Error", msg)
        self._set_status("⚠  Error occurred. See error dialog.", "#f85149")
