# gui/dashboard_tab.py — Study stats and notes history browser
import customtkinter as ctk
import os
from utils.logger import get_logger
from utils.file_utils import list_files, safe_read
from config import NOTES_DIR, SUMMARIES_DIR, FLASHCARDS_DIR, TRANSCRIPTS_DIR

logger = get_logger(__name__)


class DashboardTab(ctk.CTkFrame):
    def __init__(self, parent):
        super().__init__(parent, fg_color="transparent")
        self._build_ui()
        self._refresh_stats()

    def _build_ui(self):
        # ── Header ─────────────────────────────────────────────────────────
        ctk.CTkLabel(
            self, text="📊  Dashboard",
            font=ctk.CTkFont(family="Georgia", size=26, weight="bold"),
            text_color="#c9d1d9"
        ).pack(anchor="w", padx=24, pady=(20, 0))

        ctk.CTkLabel(
            self, text="Your study session history and statistics",
            font=ctk.CTkFont(size=12), text_color="#484f58"
        ).pack(anchor="w", padx=24)

        # ── Stats Row ──────────────────────────────────────────────────────
        stats_frame = ctk.CTkFrame(self, fg_color="transparent")
        stats_frame.pack(fill="x", padx=24, pady=16)

        self._stat_cards = {}
        stats_config = [
            ("Notes", "📝", NOTES_DIR),
            ("Summaries", "📄", SUMMARIES_DIR),
            ("Flashcard Sets", "🃏", FLASHCARDS_DIR),
            ("Transcripts", "🎙", TRANSCRIPTS_DIR),
        ]

        for i, (label, icon, path) in enumerate(stats_config):
            card = ctk.CTkFrame(
                stats_frame, fg_color="#161b22",
                corner_radius=10, border_width=1, border_color="#30363d"
            )
            card.grid(row=0, column=i, padx=6, sticky="nsew")
            stats_frame.columnconfigure(i, weight=1)

            ctk.CTkLabel(
                card, text=icon,
                font=ctk.CTkFont(size=28)
            ).pack(pady=(16, 4))

            count_lbl = ctk.CTkLabel(
                card, text="0",
                font=ctk.CTkFont(size=30, weight="bold"),
                text_color="#58a6ff"
            )
            count_lbl.pack()

            ctk.CTkLabel(
                card, text=label,
                font=ctk.CTkFont(size=12), text_color="#8b949e"
            ).pack(pady=(2, 16))

            self._stat_cards[label] = (count_lbl, path)

        # ── Main Split: File List + Viewer ─────────────────────────────────
        split = ctk.CTkFrame(self, fg_color="transparent")
        split.pack(fill="both", expand=True, padx=24, pady=(0, 16))
        split.columnconfigure(0, weight=1)
        split.columnconfigure(1, weight=2)
        split.rowconfigure(1, weight=1)

        # Left: file list with filter
        left = ctk.CTkFrame(
            split, fg_color="#161b22", corner_radius=10,
            border_width=1, border_color="#30363d"
        )
        left.grid(row=0, column=0, rowspan=2, sticky="nsew", padx=(0, 8))

        list_header = ctk.CTkFrame(left, fg_color="transparent")
        list_header.pack(fill="x", padx=12, pady=12)

        ctk.CTkLabel(
            list_header, text="Saved Files",
            font=ctk.CTkFont(size=13, weight="bold"), text_color="#c9d1d9"
        ).pack(side="left")

        ctk.CTkButton(
            list_header, text="⟳  Refresh",
            width=80, height=28,
            fg_color="#21262d", hover_color="#30363d",
            font=ctk.CTkFont(size=11),
            corner_radius=6,
            command=self._refresh_stats
        ).pack(side="right")

        # Filter dropdown
        self.filter_var = ctk.StringVar(value="Notes")
        filter_menu = ctk.CTkOptionMenu(
            left,
            values=["Notes", "Summaries", "Flashcard Sets", "Transcripts"],
            variable=self.filter_var,
            command=self._on_filter_change,
            fg_color="#21262d", button_color="#30363d",
            button_hover_color="#3d444b",
            font=ctk.CTkFont(size=12),
            corner_radius=6
        )
        filter_menu.pack(fill="x", padx=12, pady=(0, 8))

        self.file_list = ctk.CTkScrollableFrame(
            left, fg_color="#0d1117", corner_radius=6
        )
        self.file_list.pack(fill="both", expand=True, padx=8, pady=(0, 8))

        # Right: file viewer
        right_top = ctk.CTkFrame(split, fg_color="transparent")
        right_top.grid(row=0, column=1, sticky="ew", pady=(0, 8))

        ctk.CTkLabel(
            right_top, text="File Content",
            font=ctk.CTkFont(size=13, weight="bold"), text_color="#8b949e"
        ).pack(side="left")

        self.viewing_label = ctk.CTkLabel(
            right_top, text="",
            font=ctk.CTkFont(size=11), text_color="#484f58"
        )
        self.viewing_label.pack(side="left", padx=12)

        self.viewer = ctk.CTkTextbox(
            split,
            font=ctk.CTkFont(family="Courier New", size=12),
            fg_color="#161b22", text_color="#c9d1d9",
            corner_radius=8, border_width=1, border_color="#30363d",
            wrap="word", state="disabled"
        )
        self.viewer.grid(row=1, column=1, sticky="nsew")

        # Load initial list
        self._load_file_list("Notes")

    def _refresh_stats(self):
        """Update stat card counts from disk."""
        for label, (count_lbl, path) in self._stat_cards.items():
            files = list_files(path)
            count_lbl.configure(text=str(len(files)))
        self._load_file_list(self.filter_var.get())

    def _on_filter_change(self, value):
        self._load_file_list(value)

    def _load_file_list(self, category: str):
        """Populate the file list for the selected category."""
        for widget in self.file_list.winfo_children():
            widget.destroy()

        path_map = {
            "Notes": NOTES_DIR,
            "Summaries": SUMMARIES_DIR,
            "Flashcard Sets": FLASHCARDS_DIR,
            "Transcripts": TRANSCRIPTS_DIR,
        }
        directory = path_map.get(category, NOTES_DIR)
        files = list_files(directory)

        if not files:
            ctk.CTkLabel(
                self.file_list,
                text=f"No {category.lower()} saved yet.",
                font=ctk.CTkFont(size=12), text_color="#484f58"
            ).pack(pady=20)
            return

        for f in files:
            btn = ctk.CTkButton(
                self.file_list,
                text=f"  {f['name']}\n  {f['date']}",
                anchor="w",
                fg_color="transparent",
                hover_color="#21262d",
                text_color="#c9d1d9",
                font=ctk.CTkFont(size=11),
                height=48,
                corner_radius=6,
                command=lambda p=f["path"], n=f["name"]: self._view_file(p, n)
            )
            btn.pack(fill="x", pady=2, padx=4)

    def _view_file(self, path: str, name: str):
        """Display a file's content in the viewer panel."""
        content = safe_read(path)
        self.viewer.configure(state="normal")
        self.viewer.delete("1.0", "end")
        self.viewer.insert("end", content)
        self.viewer.configure(state="disabled")
        self.viewing_label.configure(text=name)
