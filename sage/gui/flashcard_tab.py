# gui/flashcard_tab.py — Flippable flashcard viewer
import customtkinter as ctk
from utils.logger import get_logger

logger = get_logger(__name__)


class FlashcardTab(ctk.CTkFrame):
    def __init__(self, parent, cards: list):
        super().__init__(parent, fg_color="transparent")
        self.cards = cards
        self.index = 0
        self.showing_question = True
        self._build_ui()

    def _build_ui(self):
        # ── Header ─────────────────────────────────────────────────────────
        hdr = ctk.CTkFrame(self, fg_color="transparent")
        hdr.pack(fill="x", padx=24, pady=(20, 0))

        ctk.CTkLabel(
            hdr, text="🃏  Flashcards",
            font=ctk.CTkFont(family="Georgia", size=26, weight="bold"),
            text_color="#c9d1d9"
        ).pack(side="left")

        if not self.cards:
            ctk.CTkLabel(
                self,
                text=(
                    "No flashcards yet.\n\n"
                    "Go to Voice Notes, record something, then press\n"
                    "'Generate Flashcards' to create cards here."
                ),
                font=ctk.CTkFont(size=14), text_color="#484f58",
                justify="center"
            ).pack(expand=True)
            return

        # ── Counter + Progress ─────────────────────────────────────────────
        self.counter_label = ctk.CTkLabel(
            self, text=f"Card 1 of {len(self.cards)}",
            font=ctk.CTkFont(size=13), text_color="#8b949e"
        )
        self.counter_label.pack(pady=(16, 8))

        self.progress_bar = ctk.CTkProgressBar(self, width=500, progress_color="#1f6feb")
        self.progress_bar.pack()
        self.progress_bar.set(1 / len(self.cards))

        # ── Card Display ───────────────────────────────────────────────────
        card_outer = ctk.CTkFrame(
            self, fg_color="#161b22",
            corner_radius=16,
            border_width=1, border_color="#30363d"
        )
        card_outer.pack(pady=24, padx=60, fill="x")

        self.side_badge = ctk.CTkLabel(
            card_outer, text="QUESTION",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#1f6feb",
            fg_color="#1f2937", corner_radius=4
        )
        self.side_badge.pack(pady=(20, 8), padx=20, anchor="w")

        self.card_text = ctk.CTkLabel(
            card_outer,
            text=self.cards[0]["question"] if self.cards else "",
            wraplength=600,
            font=ctk.CTkFont(size=18),
            text_color="#c9d1d9",
            justify="center"
        )
        self.card_text.pack(expand=True, padx=30, pady=(10, 30), fill="x")

        # ── Buttons ────────────────────────────────────────────────────────
        btn_row = ctk.CTkFrame(self, fg_color="transparent")
        btn_row.pack(pady=8)

        ctk.CTkButton(
            btn_row, text="← Prev",
            width=130, height=40,
            fg_color="#21262d", hover_color="#30363d",
            corner_radius=8,
            command=self._prev
        ).pack(side="left", padx=8)

        ctk.CTkButton(
            btn_row, text="🔄  Flip Card",
            width=160, height=40,
            fg_color="#1f6feb", hover_color="#388bfd",
            font=ctk.CTkFont(size=13, weight="bold"),
            corner_radius=8,
            command=self._flip
        ).pack(side="left", padx=8)

        ctk.CTkButton(
            btn_row, text="Next →",
            width=130, height=40,
            fg_color="#21262d", hover_color="#30363d",
            corner_radius=8,
            command=self._next
        ).pack(side="left", padx=8)

        # ── All Cards List ─────────────────────────────────────────────────
        ctk.CTkLabel(
            self, text="All Cards",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#8b949e"
        ).pack(anchor="w", padx=60, pady=(8, 4))

        scroll = ctk.CTkScrollableFrame(
            self, fg_color="#0d1117", corner_radius=8,
            border_width=1, border_color="#21262d"
        )
        scroll.pack(fill="both", expand=True, padx=60, pady=(0, 16))

        for i, card in enumerate(self.cards):
            row = ctk.CTkFrame(scroll, fg_color="#161b22", corner_radius=6)
            row.pack(fill="x", pady=3, padx=4)
            ctk.CTkLabel(
                row, text=f"  {i + 1}. {card['question']}",
                font=ctk.CTkFont(size=12), text_color="#8b949e",
                anchor="w"
            ).pack(fill="x", padx=8, pady=6)

    # ── Navigation ──────────────────────────────────────────────────────────
    def _flip(self):
        if not self.cards:
            return
        self.showing_question = not self.showing_question
        card = self.cards[self.index]
        if self.showing_question:
            self.card_text.configure(text=card["question"])
            self.side_badge.configure(text="QUESTION", text_color="#1f6feb")
        else:
            self.card_text.configure(text=card["answer"])
            self.side_badge.configure(text="ANSWER", text_color="#3fb950")

    def _next(self):
        if not self.cards:
            return
        self.index = (self.index + 1) % len(self.cards)
        self._show_card()

    def _prev(self):
        if not self.cards:
            return
        self.index = (self.index - 1) % len(self.cards)
        self._show_card()

    def _show_card(self):
        self.showing_question = True
        card = self.cards[self.index]
        self.card_text.configure(text=card["question"])
        self.side_badge.configure(text="QUESTION", text_color="#1f6feb")
        self.counter_label.configure(
            text=f"Card {self.index + 1} of {len(self.cards)}"
        )
        self.progress_bar.set((self.index + 1) / len(self.cards))
