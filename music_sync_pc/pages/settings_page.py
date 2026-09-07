"""设置页面 —— 扫描参数、外观主题。"""

from __future__ import annotations

from typing import Any

import customtkinter as ctk

from core.config import ConfigManager
from utils.constants import DIFF_DIM_CONTENT_HASH


class SettingsPage(ctk.CTkFrame):
    def __init__(self, master: Any, config: ConfigManager, **kwargs: Any) -> None:
        super().__init__(master, **kwargs)
        self.config = config
        self._theme_callback: callable | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        self.grid_columnconfigure(0, weight=1)

        scan_frame = ctk.CTkFrame(self)
        scan_frame.grid(row=0, column=0, padx=15, pady=(15, 5), sticky="ew")

        ctk.CTkLabel(scan_frame, text="扫描设置",
                     font=ctk.CTkFont(size=15, weight="bold")).grid(
            row=0, column=0, columnspan=2, padx=15, pady=(15, 10), sticky="w")

        ctk.CTkLabel(scan_frame, text="并行线程数").grid(
            row=1, column=0, padx=15, pady=5, sticky="w")
        self._workers_combo = ctk.CTkComboBox(
            scan_frame, values=["1", "2", "4", "6", "8"],
            command=self._on_workers_changed, width=100)
        self._workers_combo.set(str(self.config.max_workers))
        self._workers_combo.grid(row=1, column=1, padx=15, pady=5, sticky="w")

        ctk.CTkLabel(scan_frame, text="大文件阈值 (MB)").grid(
            row=2, column=0, padx=15, pady=5, sticky="w")
        threshold_mb = self.config.large_file_threshold // (1024 * 1024)
        self._threshold_combo = ctk.CTkComboBox(
            scan_frame, values=["50", "100", "200", "500"],
            command=self._on_threshold_changed, width=100)
        self._threshold_combo.set(str(threshold_mb))
        self._threshold_combo.grid(row=2, column=1, padx=15, pady=5, sticky="w")

        ctk.CTkLabel(scan_frame, text="扩展名过滤（空格分隔）").grid(
            row=3, column=0, padx=15, pady=5, sticky="w")
        extensions_str = " ".join(self.config.extensions)
        self._ext_entry = ctk.CTkEntry(scan_frame, width=300)
        self._ext_entry.insert(0, extensions_str)
        self._ext_entry.grid(row=3, column=1, padx=15, pady=5, sticky="w")

        ctk.CTkButton(scan_frame, text="保存设置", width=100,
                      command=self._save_settings).grid(
            row=4, column=0, columnspan=2, padx=15, pady=15)

        # ---- 差异比较设置区：file_size 强制参与；可选维度由 config.judgment_dims 决定 ----
        diff_frame = ctk.CTkFrame(self)
        diff_frame.grid(row=1, column=0, padx=15, pady=5, sticky="ew")

        ctk.CTkLabel(diff_frame, text="差异比较",
                     font=ctk.CTkFont(size=15, weight="bold")).grid(
            row=0, column=0, columnspan=2, padx=15, pady=(15, 10), sticky="w")

        # file_size 为强制基准维度：常驻开启、禁用不可取消，保证判定永不因维度集合为空失效
        self._file_size_check = ctk.CTkCheckBox(
            diff_frame, text="文件大小（始终参与）", state="disabled")
        self._file_size_check.select()
        self._file_size_check.grid(row=1, column=0, columnspan=2,
                                   padx=15, pady=5, sticky="w")

        # content_hash 为可选判定维度：勾选态由 config.judgment_dims 决定，
        # 勾选/取消即时写回配置并持久化
        self._content_hash_check = ctk.CTkCheckBox(
            diff_frame, text="内容哈希", command=self._on_content_hash_toggled)
        if DIFF_DIM_CONTENT_HASH in self.config.judgment_dims:
            self._content_hash_check.select()
        self._content_hash_check.grid(row=2, column=0, columnspan=2,
                                      padx=15, pady=5, sticky="w")

        ctk.CTkLabel(
            diff_frame,
            text="提示：哈希维度需两侧签名均含内容哈希才生效，任一侧缺值自动跳过该维度",
            font=ctk.CTkFont(size=11),
        ).grid(row=3, column=0, columnspan=2, padx=15, pady=(0, 15), sticky="w")

        appearance_frame = ctk.CTkFrame(self)
        appearance_frame.grid(row=2, column=0, padx=15, pady=5, sticky="ew")

        ctk.CTkLabel(appearance_frame, text="外观",
                     font=ctk.CTkFont(size=15, weight="bold")).grid(
            row=0, column=0, columnspan=2, padx=15, pady=(15, 10), sticky="w")

        current_theme = self.config.theme
        self._theme_combo = ctk.CTkComboBox(
            appearance_frame, values=["dark", "light"],
            command=self._on_theme_changed, width=120)
        self._theme_combo.set(current_theme)
        self._theme_combo.grid(row=1, column=0, padx=15, pady=5, sticky="w")
        ctk.CTkLabel(appearance_frame, text="（切换后立即生效）",
                     font=ctk.CTkFont(size=11)).grid(
            row=1, column=1, padx=5, pady=5, sticky="w")

        info_frame = ctk.CTkFrame(self)
        info_frame.grid(row=3, column=0, padx=15, pady=15, sticky="ew")

        ctk.CTkLabel(info_frame, text="关于 MusicSync",
                     font=ctk.CTkFont(size=15, weight="bold")).grid(
            row=0, column=0, padx=15, pady=(15, 5), sticky="w")
        ctk.CTkLabel(info_frame, text="版本: 1.0.0",
                     font=ctk.CTkFont(size=13)).grid(
            row=1, column=0, padx=15, pady=2, sticky="w")
        ctk.CTkLabel(info_frame, text="签名格式: 2.0 | 哈希: xxh64",
                     font=ctk.CTkFont(size=13)).grid(
            row=2, column=0, padx=15, pady=(2, 15), sticky="w")

    def set_theme_callback(self, callback: callable) -> None:
        self._theme_callback = callback

    def _on_workers_changed(self, value: str) -> None:
        try:
            self.config.max_workers = int(value)
        except ValueError:
            pass

    def _on_threshold_changed(self, value: str) -> None:
        try:
            threshold_mb = int(value)
            self.config.set_large_file_threshold_mb(threshold_mb)
        except ValueError:
            pass

    def _on_theme_changed(self, value: str) -> None:
        self.config.theme = value
        ctk.set_appearance_mode(value)
        if self._theme_callback:
            self._theme_callback(value)

    def _on_content_hash_toggled(self) -> None:
        """内容哈希判定维度勾选回调：将勾选态同步到 config.judgment_dims 并持久化。

        content_hash 是当前唯一可选的判定维度，采用通用增删语义：
        勾选则追加到列表尾部，取消则移除；移除后为空时写回 []，
        保证配置始终反映用户实际勾选的可选维度（不含强制维度 file_size）。
        """
        dims = self.config.judgment_dims
        if self._content_hash_check.get():
            if DIFF_DIM_CONTENT_HASH not in dims:
                dims.append(DIFF_DIM_CONTENT_HASH)
        elif DIFF_DIM_CONTENT_HASH in dims:
            dims.remove(DIFF_DIM_CONTENT_HASH)
        # setter 内部会立即 save，空列表同样落盘，避免残留旧配置
        self.config.judgment_dims = dims

    def _save_settings(self) -> None:
        try:
            workers = int(self._workers_combo.get())
            self.config.max_workers = workers
        except ValueError:
            pass

        threshold_mb_str = self._threshold_combo.get()
        try:
            threshold_mb = int(threshold_mb_str)
            self.config.set_large_file_threshold_mb(threshold_mb)
        except ValueError:
            pass

        extensions = self._ext_entry.get().strip().split()
        if extensions:
            self.config.extensions = extensions