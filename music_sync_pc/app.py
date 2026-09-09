"""主窗口 —— 标签页容器、状态栏。"""

from __future__ import annotations

import logging
from typing import Any

import customtkinter as ctk

from core.config import ConfigManager
from pages.debug_log_page import DebugLogPage
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

        # 「调试日志」页（DebugLogPage 实例）及其实例化标记，_build_ui 前完成初始化
        self.debug_log_page = None
        self._debug_log_tab_active = False

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
        self.settings_page.set_debug_log_callback(self._on_debug_log_toggled)
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

        # 配置开启调试日志时，在其它 tab 均构建完成后追加「调试日志」页
        if self.config.debug_log_enabled:
            self._show_debug_log_tab()

        # 主窗口关闭时释放配对服务端口，避免端口泄露
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _on_close(self) -> None:
        """主窗口关闭回调：先释放扫描页内的配对服务，再销毁窗口退出。"""
        if hasattr(self, "scan_page"):
            self.scan_page.on_close()
        self.destroy()

    def _on_tab_changed(self) -> None:
        tab = self._tabview.get()
        if tab == "扫描":
            self.scan_page.on_tab_activated()
        elif tab == "结果":
            # 进入结果页即刷新当前标签页列宽（空数据也按窗口宽度填充，避免溢出）
            self.result_page.refresh_layout()
            if self.scan_page.diff_report:
                # 延迟执行，等待标签页切换完成后再填充数据，避免 Tkinter 事件循环冲突导致卡死
                self.after(10, lambda: self.result_page.set_diff_report(self.scan_page.diff_report))
        elif tab == "调试日志":
            if self.debug_log_page is not None:
                # 切到调试日志页时立即刷新一次，展示最新日志（页面销毁后不会触发此处）
                self.debug_log_page.on_activated()

    def _on_debug_log_toggled(self, enabled: bool) -> None:
        """调试日志开关回调：根据开关目标状态联动显示/隐藏「调试日志」页。

        Args:
            enabled: 开关切换后的目标状态（True 显示，False 隐藏）。
        """
        if enabled:
            self._show_debug_log_tab()
        else:
            self._hide_debug_log_tab()

    def _show_debug_log_tab(self) -> None:
        """追加「调试日志」页并实例化 DebugLogPage。

        幂等：页已激活时直接返回，避免重复 add 触发 CTkTabview 同名异常；
        调用方保证在其它 tab 构建完成后执行，新 tab 仅追加不抢占当前页。
        """
        if self._debug_log_tab_active:
            return
        log_tab = self._tabview.add("调试日志")
        self.debug_log_page = DebugLogPage(log_tab)
        self.debug_log_page.pack(fill="both", expand=True, padx=2, pady=2)
        self._debug_log_tab_active = True

    def _hide_debug_log_tab(self) -> None:
        """移除「调试日志」页并释放页面实例。

        幂等：页未激活时直接返回；删除前若正停留在该页，先切回「扫描」
        避免删除当前选中页，随后删除 tab 并清空引用与激活标记。
        """
        if not self._debug_log_tab_active:
            return
        if self._tabview.get() == "调试日志":
            self._tabview.set("扫描")
        self._tabview.delete("调试日志")
        # 修复 customtkinter: CTkSegmentedButton.delete 后残留空列 weight 未清零，
        # 导致删除 tab 后顶部分段栏宽度不回缩。遍历无 widget 的列并清零其 weight。
        _seg = self._tabview._segmented_button
        _cols, _ = _seg.grid_size()
        for _col in range(_cols):
            if not _seg.grid_slaves(row=0, column=_col):
                _seg.grid_columnconfigure(_col, weight=0, minsize=0)
        self.debug_log_page = None
        self._debug_log_tab_active = False

    def _on_theme_changed(self, theme: str) -> None:
        ctk.set_appearance_mode(theme)
        if hasattr(self.result_page, "on_theme_changed"):
            self.result_page.on_theme_changed(theme)