# gui/app.py — Main application window with professional tab layout
import customtkinter as ctk
from utils.logger import get_logger
from config import APP_TITLE, APP_GEOMETRY, APP_MIN_SIZE

logger = get_logger(__name__)


class SAGEApp(ctk.CTk):
    """
    Main application window.
    Contains four tabs: Voice Notes, Flashcards, Summarizer, Dashboard.
    """
    def __init__(self):
        super().__init__()
        self.title(APP_TITLE)
        self.geometry(APP_GEOMETRY)
        self.minsize(*APP_MIN_SIZE)
        self.configure(fg_color="#0d1117")

        self._build_header()
        self._build_tabs()
        self._build_status_bar()

    def _build_header(self):
        """Top header bar with app name and version."""
        header = ctk.CTkFrame(self, fg_color="#161b22", height=55, corner_radius=0)
        header.pack(fill="x", side="top")
        header.pack_propagate(False)

        ctk.CTkLabel(
            header, text="  SAGE",
            font=ctk.CTkFont(family="Georgia", size=22, weight="bold"),
            text_color="#58a6ff"
        ).pack(side="left", padx=10, pady=10)

        ctk.CTkLabel(
            header, text="Smart Academic Guide & Engine",
            font=ctk.CTkFont(size=12),
            text_color="#8b949e"
        ).pack(side="left", pady=10)

        ctk.CTkLabel(
            header, text="Phi-3.5 · Moonshine · RAG  ",
            font=ctk.CTkFont(size=11),
            text_color="#30363d"
        ).pack(side="right", pady=10)

    def _build_tabs(self):
        """Main content area with four tabs."""
        self.tabview = ctk.CTkTabview(
            self,
            fg_color="#0d1117",
            segmented_button_fg_color="#161b22",
            segmented_button_selected_color="#1f6feb",
            segmented_button_selected_hover_color="#388bfd",
            segmented_button_unselected_color="#161b22",
            segmented_button_unselected_hover_color="#21262d",
            text_color="#c9d1d9",
            text_color_disabled="#484f58",
            corner_radius=8
        )
        self.tabview.pack(fill="both", expand=True, padx=16, pady=(8, 0))

        # Create tabs
        self.tabview.add("🎙  Voice Notes")
        self.tabview.add("🃏  Flashcards")
        self.tabview.add("📄  Summarizer")
        self.tabview.add("📊  Dashboard")

        # Lazy-import to avoid circular imports
        from gui.voice_tab import VoiceTab
        from gui.summarize_tab import SummarizeTab
        from gui.dashboard_tab import DashboardTab

        self.voice_tab = VoiceTab(
            self.tabview.tab("🎙  Voice Notes"),
            on_flashcard_request=self._open_flashcards
        )
        self.voice_tab.pack(fill="both", expand=True)

        self.summarize_tab = SummarizeTab(self.tabview.tab("📄  Summarizer"))
        self.summarize_tab.pack(fill="both", expand=True)

        self.dashboard_tab = DashboardTab(self.tabview.tab("📊  Dashboard"))
        self.dashboard_tab.pack(fill="both", expand=True)

        # Flashcard tab starts empty
        self._flashcard_container = self.tabview.tab("🃏  Flashcards")

        # Show placeholder in flashcard tab
        self._show_flashcard_placeholder()

    def _show_flashcard_placeholder(self):
        """Show empty state in flashcard tab."""
        from gui.flashcard_tab import FlashcardTab
        fc_tab = FlashcardTab(self._flashcard_container, [])
        fc_tab.pack(fill="both", expand=True)

    def _build_status_bar(self):
        """Bottom status bar."""
        bar = ctk.CTkFrame(self, fg_color="#161b22", height=28, corner_radius=0)
        bar.pack(fill="x", side="bottom")
        bar.pack_propagate(False)

        self._status_var = ctk.StringVar(value="Ready")
        ctk.CTkLabel(
            bar, textvariable=self._status_var,
            font=ctk.CTkFont(size=11),
            text_color="#8b949e"
        ).pack(side="left", padx=12, pady=4)

        ctk.CTkLabel(
            bar, text="All processing runs locally  🔒",
            font=ctk.CTkFont(size=11),
            text_color="#3d4449"
        ).pack(side="right", padx=12, pady=4)

    def set_status(self, msg: str):
        """Update the bottom status bar from any thread safely."""
        self.after(0, lambda: self._status_var.set(msg))

    def _open_flashcards(self, cards: list):
        """Rebuild flashcard tab with new cards and switch to it."""
        from gui.flashcard_tab import FlashcardTab

        for widget in self._flashcard_container.winfo_children():
            widget.destroy()

        fc_tab = FlashcardTab(self._flashcard_container, cards)
        fc_tab.pack(fill="both", expand=True)
        self.tabview.set("🃏  Flashcards")
