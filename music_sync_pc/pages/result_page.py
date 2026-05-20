"""结果页面 —— 分类展示扫描差异（新增/删除/更新）。"""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk
from typing import Any

import customtkinter as ctk

from services.diff_service import DiffReport
from utils.file_utils import format_size


class ResultPage(ctk.CTkFrame):
    def __init__(self, master: Any, **kwargs: Any) -> None:
        super().__init__(master, **kwargs)
        self.diff_report: DiffReport | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=0)
        self.grid_rowconfigure(1, weight=1)

        summary_frame = ctk.CTkFrame(self)
        summary_frame.grid(row=0, column=0, padx=15, pady=(15, 5), sticky="ew")
        summary_frame.grid_columnconfigure((0, 1, 2, 3), weight=1)

        self._added_label = ctk.CTkLabel(summary_frame, text="新增\n-",
                                         font=ctk.CTkFont(size=14), text_color="#4CAF50")
        self._added_label.grid(row=0, column=0, padx=10, pady=10)

        self._updated_label = ctk.CTkLabel(summary_frame, text="更新\n-",
                                           font=ctk.CTkFont(size=14), text_color="#2196F3")
        self._updated_label.grid(row=0, column=1, padx=10, pady=10)

        self._removed_label = ctk.CTkLabel(summary_frame, text="删除\n-",
                                           font=ctk.CTkFont(size=14), text_color="#F44336")
        self._removed_label.grid(row=0, column=2, padx=10, pady=10)

        self._unchanged_label = ctk.CTkLabel(summary_frame, text="未变\n-",
                                             font=ctk.CTkFont(size=14))
        self._unchanged_label.grid(row=0, column=3, padx=10, pady=10)

        tab_frame = ctk.CTkFrame(self)
        tab_frame.grid(row=1, column=0, padx=15, pady=5, sticky="nsew")
        tab_frame.grid_columnconfigure(0, weight=1)
        tab_frame.grid_rowconfigure(0, weight=0)
        tab_frame.grid_rowconfigure(1, weight=1)

        self._tabview = ctk.CTkTabview(tab_frame)
        self._tabview.grid(row=0, column=0, padx=5, pady=(5, 0), sticky="ew")

        self._tab_added = self._tabview.add("新增")
        self._tab_updated = self._tabview.add("更新")
        self._tab_removed = self._tabview.add("删除")

        self._tree_added = self._create_tree(self._tab_added, "#4CAF50")
        self._tree_updated = self._create_tree(self._tab_updated, "#2196F3")
        self._tree_removed = self._create_tree(self._tab_removed, "#F44336")

        self._tabview.set("新增")

        self._empty_label = ctk.CTkLabel(tab_frame, text="暂无扫描结果，请先在扫描页执行扫描",
                                         font=ctk.CTkFont(size=14))
        self._empty_label.grid(row=1, column=0, padx=10, pady=40)

    def _create_tree(self, parent: Any, tag_color: str) -> ttk.Treeview:
        parent.grid_columnconfigure(0, weight=1)
        parent.grid_rowconfigure(0, weight=1)

        columns = ("path", "artist", "size", "bitrate")
        tree = ttk.Treeview(parent, columns=columns, show="headings", height=12)
        tree.heading("path", text="文件路径")
        tree.heading("artist", text="艺术家")
        tree.heading("size", text="大小")
        tree.heading("bitrate", text="音质")

        tree.column("path", width=300, minwidth=150)
        tree.column("artist", width=150, minwidth=80)
        tree.column("size", width=80, minwidth=60, anchor="center")
        tree.column("bitrate", width=70, minwidth=60, anchor="center")

        scrollbar = ttk.Scrollbar(parent, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=scrollbar.set)
        tree.grid(row=0, column=0, sticky="nsew", padx=5, pady=5)
        scrollbar.grid(row=0, column=1, sticky="ns", pady=5)

        tree.tag_configure("colored", foreground=tag_color)
        return tree

    def _clear_trees(self) -> None:
        for tree in (self._tree_added, self._tree_updated, self._tree_removed):
            for item in tree.get_children():
                tree.delete(item)

    def _populate_tree(self, tree: ttk.Treeview, entries: list[dict[str, Any]]) -> None:
        for entry in entries:
            meta = entry.get("audio_meta", {})
            tree.insert("", "end", values=(
                entry.get("relative_path", ""),
                meta.get("artist", ""),
                format_size(entry.get("file_size", 0)),
                f"{meta.get('bitrate_kbps', '-')}kbps" if meta.get("bitrate_kbps") else "-",
            ), tags=("colored",))

    def set_diff_report(self, report: DiffReport | None) -> None:
        self.diff_report = report
        self._clear_trees()

        if report is None or not report.has_changes:
            self._empty_label.configure(text="暂无变更")
            self._added_label.configure(text="新增\n0")
            self._updated_label.configure(text="更新\n0")
            self._removed_label.configure(text="删除\n0")
            self._unchanged_label.configure(text="未变\n-")
            return

        self._empty_label.configure(text="")

        self._added_label.configure(text=f"新增\n{len(report.added)}")
        self._updated_label.configure(text=f"更新\n{len(report.updated)}")
        self._removed_label.configure(text=f"删除\n{len(report.removed)}")
        self._unchanged_label.configure(text=f"未变\n{report.unchanged}")

        self._populate_tree(self._tree_added, report.added)
        self._populate_tree(self._tree_updated, report.updated)
        self._populate_tree(self._tree_removed, report.removed)