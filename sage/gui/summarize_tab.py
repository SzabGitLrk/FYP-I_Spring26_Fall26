# gui/summarize_tab.py — Document summarizer tab
import customtkinter as ctk
from tkinter import filedialog
import threading
import os
from utils.logger import get_logger

logger = get_logger(__name__)


class SummarizeTab(ctk.CTkFrame):
    def __init__(self, parent):
        super().__init__(parent, fg_color="transparent")
        self.filepath = None
        self._last_summary = ""
        self._build_ui()

    def _build_ui(self):
        # ── Header ─────────────────────────────────────────────────────────
        hdr = ctk.CTkFrame(self, fg_color="transparent")
        hdr.pack(fill="x", padx=24, pady=(20, 0))

        ctk.CTkLabel(
            hdr, text="📄  Document Summarizer",
            font=ctk.CTkFont(family="Georgia", size=26, weight="bold"),
            text_color="#c9d1d9"
        ).pack(side="left")

        ctk.CTkLabel(
            hdr, text="Supports .pptx and .docx files",
            font=ctk.CTkFont(size=12), text_color="#484f58"
        ).pack(side="left", padx=16)

        # ── File Picker Card ───────────────────────────────────────────────
        file_card = ctk.CTkFrame(
            self, fg_color="#161b22",
            corner_radius=10, border_width=1, border_color="#30363d"
        )
        file_card.pack(fill="x", padx=24, pady=16)

        file_inner = ctk.CTkFrame(file_card, fg_color="transparent")
        file_inner.pack(fill="x", padx=20, pady=16)

        ctk.CTkButton(
            file_inner, text="📂  Browse File",
            width=160, height=40,
            fg_color="#21262d", hover_color="#30363d",
            corner_radius=8,
            command=self._pick_file
        ).pack(side="left")

        self.file_label = ctk.CTkLabel(
            file_inner, text="No file selected",
            font=ctk.CTkFont(size=13), text_color="#484f58"
        )
        self.file_label.pack(side="left", padx=16)

        self.summarize_btn = ctk.CTkButton(
            file_inner, text="⚡  Generate Summary",
            width=200, height=40,
            fg_color="#1f6feb", hover_color="#388bfd",
            font=ctk.CTkFont(size=13, weight="bold"),
            corner_radius=8,
            state="disabled",
            command=self._summarize
        )
        self.summarize_btn.pack(side="right")

        # ── Progress ───────────────────────────────────────────────────────
        prog_frame = ctk.CTkFrame(self, fg_color="transparent")
        prog_frame.pack(fill="x", padx=24, pady=(0, 8))

        self.progress = ctk.CTkProgressBar(
            prog_frame, height=6,
            progress_color="#1f6feb", fg_color="#21262d"
        )
        self.progress.pack(fill="x")
        self.progress.set(0)

        self.status_label = ctk.CTkLabel(
            self, text="",
            font=ctk.CTkFont(size=12), text_color="#8b949e"
        )
        self.status_label.pack()

        # ── Output ─────────────────────────────────────────────────────────
        ctk.CTkLabel(
            self, text="Summary Output",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#8b949e"
        ).pack(anchor="w", padx=24, pady=(8, 4))

        self.output_box = ctk.CTkTextbox(
            self,
            font=ctk.CTkFont(size=13),
            fg_color="#161b22", text_color="#c9d1d9",
            corner_radius=8, border_width=1, border_color="#30363d",
            wrap="word"
        )
        self.output_box.pack(fill="both", expand=True, padx=24, pady=(0, 16))

        # ── Save Button ────────────────────────────────────────────────────
        self.save_btn = ctk.CTkButton(
            self, text="💾  Save Summary",
            width=160, height=36,
            fg_color="#238636", hover_color="#2ea043",
            corner_radius=8, state="disabled",
            command=self._save_output
        )
        self.save_btn.pack(pady=(0, 16))

    def _pick_file(self):
        path = filedialog.askopenfilename(
            title="Select a PowerPoint or Word file",
            filetypes=[
                ("Supported files", "*.pptx *.docx"),
                ("PowerPoint", "*.pptx"),
                ("Word Document", "*.docx")
            ]
        )
        if path:
            self.filepath = path
            fname = os.path.basename(path)
            self.file_label.configure(text=f"📎  {fname}", text_color="#c9d1d9")
            self.summarize_btn.configure(state="normal")

    def _summarize(self):
        self.summarize_btn.configure(state="disabled")
        self.save_btn.configure(state="disabled")
        self.output_box.delete("1.0", "end")
        self.progress.set(0)
        self.status_label.configure(text="Starting...", text_color="#d29922")

        def _update(val, msg):
            self.after(0, lambda: self.progress.set(val))
            self.after(0, lambda: self.status_label.configure(
                text=msg, text_color="#d29922"
            ))
        
        def _stream_token(token: str):
            """Callback for streaming tokens from LLM."""
            self.after(0, lambda: self.output_box.insert("end", token))
            self.after(0, lambda: self.output_box.see("end"))  # Auto-scroll

        def _run():
            try:
                from features.summarizer import summarize_file
                summary = summarize_file(
                    self.filepath,
                    progress_callback=_update,
                    streaming_callback=_stream_token  # Stream tokens in real-time
                )
                self._last_summary = summary
                self.after(0, lambda: self.summarize_btn.configure(state="normal"))
                self.after(0, lambda: self.save_btn.configure(state="normal"))
                self.after(0, lambda: self.status_label.configure(
                    text="✅  Summary complete!", text_color="#3fb950"
                ))
            except Exception as e:
                logger.error(f"Summarizer failed: {e}")
                self.after(0, lambda: self._show_error(str(e)))
                self.after(0, lambda: self.summarize_btn.configure(state="normal"))
                self.after(0, lambda: self.status_label.configure(
                    text="⚠  Failed. See error dialog.", text_color="#f85149"
                ))

        threading.Thread(target=_run, daemon=True).start()

    def _save_output(self):
        """Let user choose where to save the summary."""
        path = filedialog.asksaveasfilename(
            defaultextension=".txt",
            filetypes=[("Text file", "*.txt")],
            title="Save Summary As"
        )
        if path:
            try:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(self._last_summary)
                self.status_label.configure(
                    text=f"✅  Saved to {path}", text_color="#3fb950"
                )
            except Exception as e:
                self._show_error(f"Save failed:\n{e}")

    def _show_error(self, msg):
        from tkinter import messagebox
        messagebox.showerror("SAGE Error", msg)
