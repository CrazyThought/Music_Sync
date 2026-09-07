"""调试日志浏览页 —— 只读展示内存环形缓冲中的实时日志，供开发调试排查使用。

通过定时轮询 core.logger 的环形缓冲（ring_snapshot），将新增日志条目
增量追加到只读文本区并自动滚动到底部；支持一键清空缓冲与文本区。
"""

from __future__ import annotations

from typing import Any

import customtkinter as ctk

from core.logger import ring_clear, ring_snapshot


class DebugLogPage(ctk.CTkFrame):
    """只读调试日志浏览页面。

    页面自创建起以固定间隔增量轮询全局环形缓冲，把自上次游标起的新增
    日志条目渲染进只读文本区；环形缓冲被外部清空时自动重置渲染游标。

    Attributes:
        _poll_interval_ms: 轮询间隔（毫秒）。
        _seen: 已渲染的日志条数游标（环形缓冲序号单调递增时递增）。
        _textbox: 只读日志文本区。
    """

    def __init__(self, master: Any, **kwargs: Any) -> None:
        super().__init__(master, **kwargs)
        self._poll_interval_ms: int = 500
        self._seen: int = 0
        self._build_ui()
        # 页面创建后立即启动增量轮询；页面被销毁后由 _poll 内守护逻辑不再续调度
        self.after(self._poll_interval_ms, self._poll)

    # ------------------------------------------------------------------
    # UI 构建
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        """构建页面：顶部标题行（标题 + 清空按钮）与正文只读文本区。"""
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)

        # ---- 顶部标题行：标题靠左，「清空」按钮靠右（列 0 拉伸将其推开）----
        ctk.CTkLabel(
            self, text="调试日志",
            font=ctk.CTkFont(size=15, weight="bold"),
        ).grid(row=0, column=0, padx=(15, 5), pady=(12, 4), sticky="w")

        ctk.CTkButton(
            self, text="清空", width=80, command=self._on_clear_clicked,
        ).grid(row=0, column=1, padx=(5, 15), pady=(12, 4), sticky="e")

        # ---- 正文：只读文本区，wrap="none" 允许超长行横向滚动 ----
        # CTkTextbox 自带随内容自动显隐的纵横滚动条，无需外挂 scrollbar；
        # 宽度/高度交由 grid(sticky="nsew") 决定，不传死值
        self._textbox = ctk.CTkTextbox(
            self,
            wrap="none",
            state="disabled",
            font=ctk.CTkFont(family="Consolas", size=12),
        )
        self._textbox.grid(
            row=1, column=0, columnspan=2, padx=15, pady=(2, 15), sticky="nsew")

    # ------------------------------------------------------------------
    # 数据刷新
    # ------------------------------------------------------------------

    def _refresh_once(self) -> None:
        """执行一次增量刷新：追加游标之后的新日志条目并滚动到底部。"""
        entries = ring_snapshot()
        if len(entries) < self._seen:
            # 环形缓冲被清空过（容量固定为 1000，FIFO 淘汰最旧条目），
            # 只能靠游标回退判断外部清空，重置后从头渲染
            self._seen = 0

        new_entries = entries[self._seen:]
        if not new_entries:
            return

        lines = [
            f"{entry['time']} [{entry['level']}] {entry['message']}\n"
            for entry in new_entries
        ]
        self._textbox.configure(state="normal")
        self._textbox.insert("end", "".join(lines))
        self._textbox.configure(state="disabled")
        self._seen = len(entries)
        # 追加非空时自动滚动到底部，保证最新日志始终可见
        self._textbox.yview_moveto(1.0)

    def _poll(self) -> None:
        """定时轮询：执行一次刷新后调度下一次。

        页面所属页签被 CTkTabview.delete 销毁后，消息队列中残留的回调
        仍可能触发 TclError；此处捕获全部异常并静默返回（不再续调度），
        同时以 winfo_exists() 双重守护续调度分支。
        """
        try:
            self._refresh_once()
        except Exception:
            return
        if self.winfo_exists():
            self.after(self._poll_interval_ms, self._poll)

    # ------------------------------------------------------------------
    # 公开接口与事件回调
    # ------------------------------------------------------------------

    def on_activated(self) -> None:
        """页面被切换为当前可见页签时由主窗口调用。

        立即执行一次刷新（等价于 _poll 单次的追加逻辑），使切页时即时
        展示最新日志并滚动到底部，无需等待下一轮轮询。
        """
        try:
            self._refresh_once()
        except Exception:
            return

    def _on_clear_clicked(self) -> None:
        """「清空」按钮回调：清空环形缓冲与文本区，并重置渲染游标。"""
        try:
            ring_clear()
            self._textbox.configure(state="normal")
            self._textbox.delete("1.0", "end")
            self._textbox.configure(state="disabled")
            self._seen = 0
        except Exception:
            return
