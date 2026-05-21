"""结果页面 —— 分类展示扫描差异（新增/删除/更新），使用 ttk.Treeview 高性能表格。"""

from __future__ import annotations

import logging
import tkinter.ttk as ttk
from typing import Any

import customtkinter as ctk

from services.diff_service import DiffReport
from utils.file_utils import format_size

logger = logging.getLogger("musicsync")

_COLUMNS = ("index", "filename", "info", "details")
_COLUMN_HEADINGS = ("#", "文件名", "艺术家 / 专辑 / 标题", "大小 / 时长 / 音质")
_TREE_STYLE_NAME = "Result.Treeview"
_TAB_NAMES = ("新增", "更新", "删除")


class ResultPage(ctk.CTkFrame):
    def __init__(self, master: Any, **kwargs: Any) -> None:
        super().__init__(master, **kwargs)
        self.diff_report: DiffReport | None = None
        self._current_theme: str = ctk.get_appearance_mode()
        self._tab_wrappers: dict[str, ctk.CTkFrame] = {}
        self._tab_trees: dict[str, ttk.Treeview] = {}
        self._build_ui()
        self._setup_tree_style()

    # ------------------------------------------------------------------
    # UI 构建
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=0)
        self.grid_rowconfigure(1, weight=1)

        # ---- 摘要栏 ----
        summary_frame = ctk.CTkFrame(self)
        summary_frame.grid(row=0, column=0, padx=10, pady=(10, 2), sticky="ew")
        summary_frame.grid_columnconfigure((0, 1, 2, 3), weight=1)

        self._added_label = ctk.CTkLabel(
            summary_frame, text="新增\n-",
            font=ctk.CTkFont(size=14, weight="bold"), text_color="#63B987",
        )
        self._added_label.grid(row=0, column=0, padx=10, pady=10)

        self._updated_label = ctk.CTkLabel(
            summary_frame, text="更新\n-",
            font=ctk.CTkFont(size=14, weight="bold"), text_color="#C1B34B",
        )
        self._updated_label.grid(row=0, column=1, padx=10, pady=10)

        self._removed_label = ctk.CTkLabel(
            summary_frame, text="删除\n-",
            font=ctk.CTkFont(size=14, weight="bold"), text_color="#D9726A",
        )
        self._removed_label.grid(row=0, column=2, padx=10, pady=10)

        self._unchanged_label = ctk.CTkLabel(
            summary_frame, text="未变\n-",
            font=ctk.CTkFont(size=14, weight="bold"),
        )
        self._unchanged_label.grid(row=0, column=3, padx=10, pady=10)

        # ---- 标签页容器 ----
        tab_frame = ctk.CTkFrame(self)
        tab_frame.grid(row=1, column=0, padx=10, pady=(2, 5), sticky="nsew")
        tab_frame.grid_columnconfigure(0, weight=1)
        tab_frame.grid_rowconfigure(0, weight=0)   # tab 按钮行
        tab_frame.grid_rowconfigure(1, weight=1)   # 内容行

        # 分段按钮 —— 紧贴顶部，无上空隙
        self._tab_bar = ctk.CTkSegmentedButton(
            tab_frame,
            values=list(_TAB_NAMES),
            command=self._on_tab_switch,
        )
        self._tab_bar.grid(row=0, column=0, padx=5, pady=(0, 2), sticky="ew")
        self._tab_bar.set("新增")

        # 内容容器 —— 紧贴分段按钮下方
        self._content_frame = ctk.CTkFrame(tab_frame, fg_color="transparent")
        self._content_frame.grid(row=1, column=0, padx=5, pady=(0, 5), sticky="nsew")
        self._content_frame.grid_columnconfigure(0, weight=1)
        self._content_frame.grid_rowconfigure(0, weight=1)

        # 为每个标签创建 Treeview + 滚动条
        for name in _TAB_NAMES:
            wrapper, tree = self._create_tree_pane(name)
            self._tab_wrappers[name] = wrapper
            self._tab_trees[name] = tree

        # 默认显示"新增"
        self._show_tab("新增")

    # ------------------------------------------------------------------
    # Treeview 面板
    # ------------------------------------------------------------------

    def _create_tree_pane(self, tab_name: str) -> tuple[ctk.CTkFrame, ttk.Treeview]:
        """为指定标签创建 Treeview + 双向滚动条，返回 (wrapper, tree)。"""
        wrapper = ctk.CTkFrame(self._content_frame, fg_color="transparent")
        wrapper.grid_columnconfigure(0, weight=1)
        wrapper.grid_rowconfigure(0, weight=1)
        wrapper.grid_rowconfigure(1, weight=0)

        tree = ttk.Treeview(
            wrapper,
            columns=_COLUMNS,
            show="headings",
            selectmode="none",
            style=_TREE_STYLE_NAME,
        )
        tree.grid(row=0, column=0, sticky="nsew")

        # 纵向滚动条
        scrollbar_y = ctk.CTkScrollbar(wrapper, orientation="vertical", command=tree.yview)
        scrollbar_y.grid(row=0, column=1, sticky="ns")
        tree.configure(yscrollcommand=scrollbar_y.set)

        # 横向滚动条
        scrollbar_x = ctk.CTkScrollbar(wrapper, orientation="horizontal", command=tree.xview)
        scrollbar_x.grid(row=1, column=0, sticky="ew")
        tree.configure(xscrollcommand=scrollbar_x.set)

        # 列配置
        tree.heading("index", text=_COLUMN_HEADINGS[0])
        tree.heading("filename", text=_COLUMN_HEADINGS[1])
        tree.heading("info", text=_COLUMN_HEADINGS[2])
        tree.heading("details", text=_COLUMN_HEADINGS[3])

        tree.column("index", width=60, minwidth=60, stretch=False, anchor="center")
        tree.column("filename", width=320, minwidth=180, stretch=True, anchor="w")
        tree.column("info", width=300, minwidth=180, stretch=True, anchor="w")
        tree.column("details", width=280, minwidth=240, stretch=True, anchor="w")

        return wrapper, tree

    # ------------------------------------------------------------------
    # 标签切换
    # ------------------------------------------------------------------

    def _show_tab(self, tab_name: str) -> None:
        """只显示指定标签的 wrapper，隐藏其余。"""
        for name, wrapper in self._tab_wrappers.items():
            if name == tab_name:
                wrapper.grid(row=0, column=0, sticky="nsew")
            else:
                wrapper.grid_remove()

    def _on_tab_switch(self, value: str) -> None:
        self._show_tab(value)

    # ------------------------------------------------------------------
    # ttk 样式
    # ------------------------------------------------------------------

    def _setup_tree_style(self) -> None:
        """根据当前主题配置 Treeview 样式。"""
        is_dark = ctk.get_appearance_mode().lower() == "dark"

        if is_dark:
            bg = "#2B2B2B"
            fg = "#DCE4EE"
            heading_bg = "#3B3B3B"
            field_bg = "#343638"
            alt_bg = "#363636"
            sel_bg = "#1F538D"
        else:
            bg = "#F9F9FA"
            fg = "#1A1A1A"
            heading_bg = "#EBEBEC"
            field_bg = "#FFFFFF"
            alt_bg = "#F0F0F1"
            sel_bg = "#3478F6"

        style = ttk.Style()
        style.theme_use("clam")
        style.configure(
            _TREE_STYLE_NAME,
            background=bg,
            foreground=fg,
            fieldbackground=field_bg,
            rowheight=50,
            font=("Segoe UI", 15),
            borderwidth=0,
        )
        style.configure(
            f"{_TREE_STYLE_NAME}.Heading",
            background=heading_bg,
            foreground=fg,
            font=("Segoe UI", 15, "bold"),
            borderwidth=0,
        )
        style.map(
            _TREE_STYLE_NAME,
            background=[("selected", sel_bg)],
            foreground=[("selected", fg)],
        )

        # 交替行颜色
        for tree in self._tab_trees.values():
            tree.tag_configure("even", background=bg)
            tree.tag_configure("odd", background=alt_bg)

        self._current_theme = "Dark" if is_dark else "Light"

    # ------------------------------------------------------------------
    # 数据填充
    # ------------------------------------------------------------------

    def _populate_treeview(self, tree: ttk.Treeview, entries: list[dict[str, Any]]) -> None:
        """清空 Treeview 并用 entries 数据重新填充。"""
        tree.delete(*tree.get_children())

        for i, entry in enumerate(entries):
            meta = entry.get("audio_meta", {})
            path = entry.get("relative_path", "")
            artist = meta.get("artist", "")
            album = meta.get("album", "")
            title = meta.get("title", "")
            size = format_size(entry.get("file_size", 0))
            duration = meta.get("duration_secs")
            duration_str = (
                f"{int(duration // 60)}:{int(duration % 60):02d}" if duration else "-"
            )
            bitrate = (
                f"{meta.get('bitrate_kbps', '-')}kbps" if meta.get("bitrate_kbps") else "-"
            )

            info_text = " | ".join(filter(None, [artist, album, title]))
            details_text = f"大小: {size}  |  时长: {duration_str}  |  音质: {bitrate}"

            tag = "even" if i % 2 == 0 else "odd"
            tree.insert("", "end", values=(i + 1, path, info_text, details_text), tags=(tag,))

    # ------------------------------------------------------------------
    # 公开接口
    # ------------------------------------------------------------------

    def set_diff_report(self, report: DiffReport | None) -> None:
        self.diff_report = report

        if report is None:
            logger.info("set_diff_report: report is None")
            self._added_label.configure(text="新增\n0")
            self._updated_label.configure(text="更新\n0")
            self._removed_label.configure(text="删除\n0")
            self._unchanged_label.configure(text="未变\n-")
            for tree in self._tab_trees.values():
                tree.delete(*tree.get_children())
            return

        logger.info(
            "set_diff_report: added=%d, updated=%d, removed=%d, unchanged=%d, has_changes=%s",
            len(report.added),
            len(report.updated),
            len(report.removed),
            report.unchanged,
            report.has_changes,
        )

        self._added_label.configure(text=f"新增\n{len(report.added)}")
        self._updated_label.configure(text=f"更新\n{len(report.updated)}")
        self._removed_label.configure(text=f"删除\n{len(report.removed)}")
        self._unchanged_label.configure(text=f"未变\n{report.unchanged}")

        if not report.has_changes:
            for tree in self._tab_trees.values():
                tree.delete(*tree.get_children())
            return

        logger.info(
            "展示新增=%d 条，更新=%d 条，删除=%d 条",
            len(report.added),
            len(report.updated),
            len(report.removed),
        )

        self._populate_treeview(self._tab_trees["新增"], report.added)
        self._populate_treeview(self._tab_trees["更新"], report.updated)
        self._populate_treeview(self._tab_trees["删除"], report.removed)

    def on_theme_changed(self, theme: str) -> None:
        """主题切换时重新应用 Treeview 样式。"""
        self._setup_tree_style()