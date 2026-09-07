"""结果页面 —— 分类展示扫描差异（新增/删除/更新），使用 ttk.Treeview 高性能表格。

自适应布局说明：
- 列宽按「当前标签页内容」估算的最长文本自适应扩张；内容短时各列均分填满可视宽度，
  空列表/短列表不会超出窗口，也不出现无效的横向滚动条。
- 仅当内容实际宽度超过 Treeview 可视宽度时才显示横向滚动条，此时列宽保持内容宽度，
  可通过横向滚动查看被拉长的完整文本。
"""

from __future__ import annotations

import logging
import tkinter.font as tkfont
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

# 列表字体：标题与行内容统一 14px，与页面其它文本（摘要数字）字号保持一致
_TREE_FONT_FAMILY: str = "Segoe UI"
_TREE_FONT_SIZE: int = 14
_TREE_ROW_FONT: tuple[str, int] = (_TREE_FONT_FAMILY, _TREE_FONT_SIZE)
_TREE_HEADING_FONT: tuple[str, int, str] = (_TREE_FONT_FAMILY, _TREE_FONT_SIZE, "bold")

_INDEX_COL_WIDTH: int = 60          # 序号列固定宽度
_DATA_COLS: tuple[str, str, str] = ("filename", "info", "details")
_COL_TEXT_PAD: int = 34             # 单元格文本左右留白 + 安全余量，避免文本贴边/被裁切

# 差异判定维度 id → 中文说明：diff_service 在"更新"条目内部键 _diff_dims 中记录的
# 维度 id（与 utils/constants.py 保持一致），此处映射为可读文案供 UI 展示触发依据
_DIFF_DIM_LABELS: dict[str, str] = {
    "file_size": "文件大小",
    "content_hash": "内容哈希",
}


class ResultPage(ctk.CTkFrame):
    def __init__(self, master: Any, **kwargs: Any) -> None:
        super().__init__(master, **kwargs)
        self.diff_report: DiffReport | None = None
        self._current_theme: str = ctk.get_appearance_mode()
        self._current_tab: str = _TAB_NAMES[0]
        self._tab_wrappers: dict[str, ctk.CTkFrame] = {}
        self._tab_trees: dict[str, ttk.Treeview] = {}
        self._tab_xscrollbars: dict[str, ctk.CTkScrollbar] = {}
        # 各标签页按内容估算的列宽（key: 列名），用于响应式布局；空数据时为标题宽度
        self._needed_widths: dict[str, dict[str, int]] = {}
        self._init_measure_fonts()
        self._build_ui()
        self._setup_tree_style()

    # ------------------------------------------------------------------
    # 字体测量
    # ------------------------------------------------------------------

    def _init_measure_fonts(self) -> None:
        """初始化文本宽度估算用的测量字体（失败时回退 Tk 默认字体）。"""
        try:
            self._row_measure_font = tkfont.Font(font=_TREE_ROW_FONT)
        except Exception:
            self._row_measure_font = tkfont.nametofont("TkDefaultFont")
        try:
            self._heading_measure_font = tkfont.Font(font=_TREE_HEADING_FONT)
        except Exception:
            self._heading_measure_font = tkfont.nametofont("TkDefaultFont")

    @staticmethod
    def _text_width_px(text: str, font: tkfont.Font) -> int:
        """估算文本在指定字体下的像素宽度。

        直接使用 Tk 字体的真实度量（Windows 上 CJK 字形由系统回退字体
        参与度量，实测与显示宽度一致），结果最贴近实际渲染宽度。
        """
        if not text:
            return 0
        return int(font.measure(text))

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
        self._tab_bar.set(_TAB_NAMES[0])

        # 内容容器 —— 紧贴分段按钮下方
        self._content_frame = ctk.CTkFrame(tab_frame, fg_color="transparent")
        self._content_frame.grid(row=1, column=0, padx=5, pady=(0, 5), sticky="nsew")
        self._content_frame.grid_columnconfigure(0, weight=1)
        self._content_frame.grid_rowconfigure(0, weight=1)

        # 为每个标签创建 Treeview + 滚动条，并绑定尺寸自适应
        for name in _TAB_NAMES:
            wrapper, tree = self._create_tree_pane(name)
            self._tab_wrappers[name] = wrapper
            self._tab_trees[name] = tree
            wrapper.bind("<Configure>", lambda e, n=name: self._on_pane_configure(e, n))

        # 默认显示"新增"，并把空数据的初始列宽设为标题宽度
        self._show_tab(_TAB_NAMES[0])
        for name in _TAB_NAMES:
            self._needed_widths[name] = self._compute_heading_needed()

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

        # 横向滚动条：初始隐藏，仅当内容宽度超过可视宽度时才显示（由 _apply_tree_layout 控制）
        scrollbar_x = ctk.CTkScrollbar(wrapper, orientation="horizontal", command=tree.xview)
        self._tab_xscrollbars[tab_name] = scrollbar_x
        tree.configure(xscrollcommand=scrollbar_x.set)

        # 列配置
        tree.heading("index", text=_COLUMN_HEADINGS[0])
        tree.heading("filename", text=_COLUMN_HEADINGS[1])
        tree.heading("info", text=_COLUMN_HEADINGS[2])
        tree.heading("details", text=_COLUMN_HEADINGS[3])

        tree.column("index", width=_INDEX_COL_WIDTH, minwidth=_INDEX_COL_WIDTH,
                    stretch=False, anchor="center")
        # 数据列 stretch=False：列宽完全由 _apply_tree_layout 按内容与窗口宽度控制，
        # 避免 ttk 在内容超宽时自动压缩列宽（否则无法通过横向滚动查看完整内容）
        for col in _DATA_COLS:
            tree.column(col, width=100, minwidth=40, stretch=False, anchor="w")

        return wrapper, tree

    # ------------------------------------------------------------------
    # 响应式列宽
    # ------------------------------------------------------------------

    def _compute_heading_needed(self) -> dict[str, int]:
        """计算仅含标题时各数据列需要的最小宽度（作为空数据兜底宽度）。"""
        return {
            col: self._text_width_px(_COLUMN_HEADINGS[idx], self._heading_measure_font) + _COL_TEXT_PAD
            for idx, col in enumerate(_DATA_COLS, start=1)
        }

    def _content_needed(
        self,
        rows: list[tuple[str, str, str]],
    ) -> dict[str, int]:
        """根据内容最长文本估算各数据列宽度，并与标题宽度取较大值。

        Args:
            rows: 每行按 _DATA_COLS 顺序的 (filename, info, details) 文本元组列表。

        Returns:
            各数据列（filename/info/details）的估算宽度（像素），已含单元格留白。
        """
        heading_raw = {
            col: self._text_width_px(_COLUMN_HEADINGS[idx], self._heading_measure_font)
            for idx, col in enumerate(_DATA_COLS, start=1)
        }
        max_content = {col: 0 for col in _DATA_COLS}
        for filename, info, details in rows:
            for col, text in zip(_DATA_COLS, (filename, info, details)):
                w = self._text_width_px(text, self._row_measure_font)
                if w > max_content[col]:
                    max_content[col] = w
        return {
            col: max(max_content[col], heading_raw[col]) + _COL_TEXT_PAD
            for col in _DATA_COLS
        }

    def _apply_tree_layout(self, tab_name: str) -> bool:
        """按当前标签页内容与可视宽度调整列宽及横向滚动条显隐。

        规则：
        - 内容（估算）总宽不超过可视宽度：各数据列在内容宽度基础上均分
          剩余空间填满可视宽度，隐藏横向滚动条（内容不会溢出窗口）；
        - 内容总宽超过可视宽度：各数据列保持内容所需宽度，显示横向滚动条，
          用户可水平滚动查看完整内容。

        Returns:
            是否成功完成布局（True 表示树已映射且宽度有效）；树尚未映射
            时返回 False，等待 <Configure> 事件再布局。
        """
        tree = self._tab_trees[tab_name]
        needed = self._needed_widths.get(tab_name)
        if needed is None:
            return False
        view_width = tree.winfo_width()
        if view_width is None or view_width <= 1:
            return False

        total_content = _INDEX_COL_WIDTH + sum(needed.values())
        if total_content <= view_width:
            # 内容不超宽：按各列内容宽度占比分摊剩余空间以填满可视宽度，
            # 长内容列获得更多空间，保证列表贴合窗口且不产生无效横向滚动条
            extra = view_width - total_content
            total_needed = sum(needed.values())
            width_map: list[int] = []
            allocated = 0
            for col in _DATA_COLS:
                share = int(extra * needed[col] / total_needed) if total_needed else 0
                width_map.append(needed[col] + share)
                allocated += share
            width_map[-1] += extra - allocated  # 余数补到最后一列，恰好等于可视宽度
            for col, w in zip(_DATA_COLS, width_map):
                tree.column(col, width=w)
            self._set_xscrollbar_visible(tab_name, False)
        else:
            # 内容超宽：保持内容宽度，启用横向滚动
            for col in _DATA_COLS:
                tree.column(col, width=needed[col])
            self._set_xscrollbar_visible(tab_name, True)
        tree.column("index", width=_INDEX_COL_WIDTH)
        return True

    def _set_xscrollbar_visible(self, tab_name: str, visible: bool) -> None:
        """显示或隐藏指定标签页的横向滚动条。"""
        scrollbar = self._tab_xscrollbars.get(tab_name)
        if scrollbar is None:
            return
        if visible:
            scrollbar.grid(row=1, column=0, sticky="ew")
        else:
            scrollbar.grid_remove()

    def _on_pane_configure(self, event: Any, tab_name: str) -> None:
        """面板尺寸变化时重新自适应列宽（仅对当前可见面板生效）。

        面板刚映射时树宽度可能尚未就绪（winfo_width 为 1），此时布局会返回
        False，进入有界轮询重试，待几何信息稳定后补做布局。
        """
        if not event.widget.winfo_ismapped():
            return
        if not self._apply_tree_layout(tab_name):
            self._retry_layout_later(tab_name)

    def _retry_layout_later(self, tab_name: str, attempts_left: int = 10) -> None:
        """有界延迟重试列宽布局，直到树宽度就绪并布局成功。

        Tab/窗口切换时几何布局是分帧完成的，树宽度可能延迟才有效；
        这里以 60ms 间隔轮询（最多 attempts_left 次），布局成功即停止。
        """
        wrapper = self._tab_wrappers.get(tab_name)
        if wrapper is None or not wrapper.winfo_exists():
            return
        if self._apply_tree_layout(tab_name):
            return
        if attempts_left <= 0:
            return

        def _do_retry() -> None:
            try:
                self._retry_layout_later(tab_name, attempts_left - 1)
            except Exception:
                pass

        self.after(60, _do_retry)

    # ------------------------------------------------------------------
    # 标签切换
    # ------------------------------------------------------------------

    def _show_tab(self, tab_name: str) -> None:
        """只显示指定标签的 wrapper，隐藏其余，并调度一次列宽自适应。"""
        self._current_tab = tab_name
        for name, wrapper in self._tab_wrappers.items():
            if name == tab_name:
                wrapper.grid(row=0, column=0, sticky="nsew")
            else:
                wrapper.grid_remove()
        # 切换后等待面板完成映射再布局（延迟重试覆盖几何未就绪的情况）
        self._retry_layout_later(tab_name)

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
        # 行内容与列标题字号统一为 14px，与页面其它文本保持一致
        style.configure(
            _TREE_STYLE_NAME,
            background=bg,
            foreground=fg,
            fieldbackground=field_bg,
            rowheight=50,
            font=_TREE_ROW_FONT,
            borderwidth=0,
        )
        style.configure(
            f"{_TREE_STYLE_NAME}.Heading",
            background=heading_bg,
            foreground=fg,
            font=_TREE_HEADING_FONT,
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

    def _populate_treeview(
        self,
        tree: ttk.Treeview,
        entries: list[dict[str, Any]],
        tab_name: str,
    ) -> None:
        """清空 Treeview 并用 entries 数据重新填充，同时按内容估算列宽。"""
        tree.delete(*tree.get_children())

        # 收集各列渲染文本用于内容宽度估算（只统计，不参与显示）
        row_texts: list[tuple[str, str, str]] = []

        for i, raw_entry in enumerate(entries):
            # diff_service 会给"更新"条目附加内部键 _diff_dims（触发更新的判定维度 id）。
            # 先浅拷贝剔除该内部键，避免其泄漏进标准字段渲染，且不改动上游传入的原始条目
            entry = dict(raw_entry)
            diff_dims: list[str] | None = entry.pop("_diff_dims", None)

            meta = entry.get("audio_meta", {})
            path = entry.get("relative_path", "")
            artist = meta.get("artist", "")
            album = meta.get("album", "")
            title = meta.get("title", "")
            size = format_size(entry.get("file_size", 0))
            duration_ms = meta.get("duration_ms") or 0
            duration_secs = duration_ms // 1000
            duration_str = (
                f"{duration_secs // 60}:{duration_secs % 60:02d}" if duration_ms else "-"
            )
            bitrate = (
                f"{meta.get('bitrate_kbps', '-')}kbps" if meta.get("bitrate_kbps") else "-"
            )

            info_text = " | ".join(filter(None, [artist, album, title]))
            details_text = f"大小: {size}  |  时长: {duration_str}  |  音质: {bitrate}"
            if diff_dims:
                # 仅在"更新"行存在内部依据键：按映射输出可读文案，未知 id 原样兜底
                basis = "、".join(_DIFF_DIM_LABELS.get(dim, dim) for dim in diff_dims)
                details_text += f" | 依据: {basis}"

            row_texts.append((path, info_text, details_text))
            tag = "even" if i % 2 == 0 else "odd"
            tree.insert("", "end", values=(i + 1, path, info_text, details_text), tags=(tag,))

        # 记录本标签页内容所需宽度并立即自适应；树尚未映射时延迟重试
        self._needed_widths[tab_name] = self._content_needed(row_texts)
        if tab_name == self._current_tab and not self._apply_tree_layout(tab_name):
            self._retry_layout_later(tab_name)

    # ------------------------------------------------------------------
    # 公开接口
    # ------------------------------------------------------------------

    def _clear_trees(self) -> None:
        """清空全部标签页行数据，并把列宽重置为标题宽度兜底。"""
        for name, tree in self._tab_trees.items():
            tree.delete(*tree.get_children())
            self._needed_widths[name] = self._compute_heading_needed()
        if self._tab_trees.get(self._current_tab) is not None:
            if not self._apply_tree_layout(self._current_tab):
                self._retry_layout_later(self._current_tab)

    def refresh_layout(self) -> None:
        """结果页被激活时刷新当前标签页的列宽布局（适配窗口尺寸）。"""
        if not self._apply_tree_layout(self._current_tab):
            self._retry_layout_later(self._current_tab)

    def set_diff_report(self, report: DiffReport | None) -> None:
        self.diff_report = report

        if report is None:
            logger.info("set_diff_report: report is None")
            self._added_label.configure(text="新增\n0")
            self._updated_label.configure(text="更新\n0")
            self._removed_label.configure(text="删除\n0")
            self._unchanged_label.configure(text="未变\n-")
            self._clear_trees()
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
            self._clear_trees()
            return

        logger.info(
            "展示新增=%d 条，更新=%d 条，删除=%d 条",
            len(report.added),
            len(report.updated),
            len(report.removed),
        )

        self._populate_treeview(self._tab_trees["新增"], report.added, "新增")
        self._populate_treeview(self._tab_trees["更新"], report.updated, "更新")
        self._populate_treeview(self._tab_trees["删除"], report.removed, "删除")

    def on_theme_changed(self, theme: str) -> None:
        """主题切换时重新应用 Treeview 样式。"""
        self._setup_tree_style()
