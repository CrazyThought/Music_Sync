"""主窗口 —— 标签页容器、状态栏。"""

from __future__ import annotations

import logging
from typing import Any

import customtkinter as ctk

from core.config import ConfigManager
from pages.scan_page import ScanPage
from pages.result_page import ResultPage
from pages.settings_page import SettingsPage

logger = logging.getLogger("musicsync")


class App(ctk.CTk):
    def __init__(self, config: ConfigManager) -> None:
        super().__init__()
        self.config = config
        self.title("MusicSync")
        self.geometry("900x650")
        self.minsize(700, 500)

        ctk.set_appearance_mode(config.theme)
        ctk.set_default_color_theme("blue")

        self._build_ui()

    def _build_ui(self) -> None:
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=0)

        self._tabview = ctk.CTkTabview(self)
        self._tabview.grid(row=0, column=0, padx=10, pady=(10, 0), sticky="nsew")

        scan_tab = self._tabview.add("扫描")
        result_tab = self._tabview.add("结果")
        settings_tab = self._tabview.add("设置")

        self.scan_page = ScanPage(scan_tab, self.config)
        self.scan_page.pack(fill="both", expand=True, padx=2, pady=2)

        self.result_page = ResultPage(result_tab)
        self.result_page.pack(fill="both", expand=True, padx=2, pady=2)

        self.settings_page = SettingsPage(settings_tab, self.config)
        self.settings_page.set_theme_callback(self._on_theme_changed)
        self.settings_page.pack(fill="both", expand=True, padx=2, pady=2)

        self._tabview.set("扫描")

        # 让顶部 tabbar 撑满宽度
        self._tabview._segmented_button.grid_configure(sticky="nsew")

        self._status_bar = ctk.CTkLabel(
            self,
            text="就绪",
            font=ctk.CTkFont(size=11),
            anchor="w",
        )
        self._status_bar.grid(row=1, column=0, padx=15, pady=(2, 8), sticky="ew")

        self._tabview.configure(command=self._on_tab_changed)

    def _on_tab_changed(self) -> None:
        tab = self._tabview.get()
        if tab == "扫描":
            self.scan_page.on_tab_activated()
        elif tab == "结果":
            if self.scan_page.diff_report:
                # 延迟执行，等待标签页切换完成后再填充数据，避免 Tkinter 事件循环冲突导致卡死
                self.after(10, lambda: self.result_page.set_diff_report(self.scan_page.diff_report))

    def _on_theme_changed(self, theme: str) -> None:
        ctk.set_appearance_mode(theme)
        if hasattr(self.result_page, "on_theme_changed"):
            self.result_page.on_theme_changed(theme)