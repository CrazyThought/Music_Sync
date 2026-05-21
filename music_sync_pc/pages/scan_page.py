"""扫描页面 —— 路径配置、扫描触发、进度显示。"""

from __future__ import annotations

import logging
import threading
from pathlib import Path
from tkinter import filedialog
from typing import Any

import customtkinter as ctk

from core.config import ConfigManager
from services.scanner import MusicScanner
from services.signature import save_signature, load_signature
from services.diff_service import compare_signatures, DiffReport
from utils.file_utils import format_size

logger = logging.getLogger("musicsync")


class ScanPage(ctk.CTkFrame):
    def __init__(self, master: Any, config: ConfigManager, **kwargs: Any) -> None:
        super().__init__(master, **kwargs)
        self.config = config
        self.scan_result: dict[str, Any] | None = None
        self.diff_report: DiffReport | None = None
        self._scanning = False

        self._build_ui()
        self._refresh_state()

    def _build_ui(self) -> None:
        self.grid_columnconfigure(0, weight=1)

        path_frame = ctk.CTkFrame(self)
        path_frame.grid(row=0, column=0, padx=15, pady=(15, 5), sticky="ew")
        path_frame.grid_columnconfigure(0, weight=0)
        path_frame.grid_columnconfigure(1, weight=1)
        path_frame.grid_columnconfigure(2, weight=0)

        ctk.CTkLabel(path_frame, text="音乐文件夹",
                     font=ctk.CTkFont(size=13, weight="bold")).grid(
            row=0, column=0, columnspan=3, padx=10, pady=(10, 2), sticky="w")

        self._music_entry = ctk.CTkEntry(path_frame, placeholder_text="请选择音乐文件夹...")
        self._music_entry.grid(row=1, column=0, padx=(10, 5), pady=(0, 10), sticky="ew", columnspan=2)

        ctk.CTkButton(path_frame, text="选择", width=60,
                      command=self._choose_music_folder).grid(
            row=1, column=2, padx=(0, 10), pady=(0, 10))

        ctk.CTkLabel(path_frame, text="签名导出位置",
                     font=ctk.CTkFont(size=13, weight="bold")).grid(
            row=2, column=0, columnspan=3, padx=10, pady=(5, 2), sticky="w")

        self._output_entry = ctk.CTkEntry(path_frame, placeholder_text="签名文件保存位置...")
        self._output_entry.grid(row=3, column=0, padx=(10, 5), pady=(0, 10), sticky="ew", columnspan=2)

        ctk.CTkButton(path_frame, text="选择", width=60,
                      command=self._choose_output_folder).grid(
            row=3, column=2, padx=(0, 10), pady=(0, 10))

        stats_frame = ctk.CTkFrame(self)
        stats_frame.grid(row=1, column=0, padx=15, pady=5, sticky="ew")
        stats_frame.grid_columnconfigure((0, 1, 2), weight=1)

        self._total_label = ctk.CTkLabel(stats_frame, text="总文件数\n-",
                                         font=ctk.CTkFont(size=14))
        self._total_label.grid(row=0, column=0, padx=15, pady=15)

        self._size_label = ctk.CTkLabel(stats_frame, text="总大小\n-",
                                        font=ctk.CTkFont(size=14))
        self._size_label.grid(row=0, column=1, padx=15, pady=15)

        self._last_scan_label = ctk.CTkLabel(stats_frame, text="上次扫描\n-",
                                             font=ctk.CTkFont(size=14))
        self._last_scan_label.grid(row=0, column=2, padx=15, pady=15)

        action_frame = ctk.CTkFrame(self)
        action_frame.grid(row=2, column=0, padx=15, pady=5, sticky="ew")
        action_frame.grid_columnconfigure(0, weight=1)

        self._scan_btn = ctk.CTkButton(action_frame, text="开始扫描",
                                       height=36, command=self._start_scan)
        self._scan_btn.grid(row=0, column=0, padx=10, pady=(10, 2), sticky="ew")

        self._progress = ctk.CTkProgressBar(action_frame, progress_color="#00BCD4", height=8)
        self._progress.set(0)
        self._progress.grid_forget()

        self._status_label = ctk.CTkLabel(action_frame, text="",
                                          font=ctk.CTkFont(size=12))
        self._status_label.grid(row=1, column=0, padx=10, pady=(2, 10))

        export_frame = ctk.CTkFrame(self)
        export_frame.grid(row=3, column=0, padx=15, pady=5, sticky="ew")
        export_frame.grid_columnconfigure(0, weight=1)
        export_frame.grid_columnconfigure(1, weight=1)

        self._export_btn = ctk.CTkButton(export_frame, text="导出签名文件",
                                         height=36, command=self._export_signature,
                                         state="disabled")
        self._export_btn.grid(row=0, column=0, padx=(10, 5), pady=10, sticky="ew")

        self._import_btn = ctk.CTkButton(export_frame, text="导入特征文件",
                                         height=36, command=self._import_signature)
        self._import_btn.grid(row=0, column=1, padx=(5, 10), pady=10, sticky="ew")

    def _choose_music_folder(self) -> None:
        folder = filedialog.askdirectory(title="选择音乐文件夹")
        if folder:
            self._music_entry.delete(0, "end")
            self._music_entry.insert(0, folder)
            self.config.music_folder = folder

    def _choose_output_folder(self) -> None:
        folder = filedialog.askdirectory(title="选择签名文件保存位置")
        if folder:
            self._output_entry.delete(0, "end")
            self._output_entry.insert(0, folder)
            self.config.output_folder = folder

    def _refresh_state(self) -> None:
        """刷新路径输入框和统计标签，不覆盖内存中的扫描数据。"""
        music_folder = self.config.music_folder
        if music_folder:
            self._music_entry.delete(0, "end")
            self._music_entry.insert(0, music_folder)
        output_folder = self.config.output_folder
        if output_folder:
            self._output_entry.delete(0, "end")
            self._output_entry.insert(0, output_folder)

        last = self.config.last_scan
        if last:
            total = last.get("total_files", 0)
            total_size = last.get("total_size_bytes", 0)
            ts = last.get("timestamp", 0)
            from datetime import datetime
            time_str = datetime.fromtimestamp(ts / 1000).strftime("%m-%d %H:%M") if ts else "-"
            self._total_label.configure(text=f"总文件数\n{total}")
            self._size_label.configure(text=f"总大小\n{format_size(total_size)}")
            self._last_scan_label.configure(text=f"上次扫描\n{time_str}")

    def _start_scan(self) -> None:
        music_folder = self._music_entry.get().strip()
        if not music_folder:
            self._status_label.configure(text="请先选择音乐文件夹")
            return
        if not Path(music_folder).is_dir():
            self._status_label.configure(text="音乐文件夹路径无效")
            return

        if self._scanning:
            return
        self._scanning = True
        self._scan_btn.configure(state="disabled", text="扫描中...")
        self._status_label.configure(text="正在扫描...")
        self._progress.grid(row=1, column=0, padx=10, pady=(2, 2), sticky="ew")
        self._progress.set(0)
        self._progress.start()

        # 新扫描前清除历史数据和差异报告
        self.scan_result = None
        self.diff_report = None

        threading.Thread(target=self._run_scan, args=(music_folder, True), daemon=True).start()

    def _run_scan(self, music_folder: str, clear_previous: bool = False) -> None:
        try:
            scanner = MusicScanner(
                root_path=Path(music_folder),
                max_workers=self.config.max_workers,
            )
            previous = None
            output_dir = Path(self.config.output_folder)
            sig_path = output_dir / "pc_signature.json"
            if not clear_previous and sig_path.exists():
                try:
                    previous = load_signature(sig_path)
                except (OSError, ValueError, FileNotFoundError):
                    pass

            result = scanner.scan(previous)
            self.scan_result = result

            if previous:
                try:
                    self.diff_report = compare_signatures(result, previous)
                except (KeyError, TypeError, ValueError):
                    self.diff_report = None

            self.config.last_scan = {
                "timestamp": result["generated_at"],
                "total_files": result["scan_summary"]["total_files"],
                "total_size_bytes": result["scan_summary"]["total_size_bytes"],
                "signature_file": str(sig_path),
            }

            self.after(0, self._on_scan_done)
        except (OSError, PermissionError, ValueError) as e:
            logger.exception("扫描失败")
            self.after(0, lambda: self._on_scan_error(str(e)))

    def _on_scan_done(self) -> None:
        self._scanning = False
        self._progress.stop()
        self._progress.grid_forget()
        self._scan_btn.configure(state="normal", text="开始扫描")
        self._export_btn.configure(state="normal")

        if self.scan_result:
            summary = self.scan_result["scan_summary"]
            total = summary["total_files"]
            total_size = summary["total_size_bytes"]
            duration = summary["scan_duration_ms"]
            msg = f"扫描完成：{total} 个文件，{format_size(total_size)}，耗时 {duration / 1000:.1f}s"
            if self.diff_report and self.diff_report.has_changes:
                msg += f" | 变更 {self.diff_report.total_changes} 项"
            self._status_label.configure(text=msg)
        else:
            self._status_label.configure(text="扫描完成，未生成结果")

        # 只刷新 UI 显示，不重新加载 scan_result（避免覆盖新扫描数据）
        music_folder = self.config.music_folder
        if music_folder:
            self._music_entry.delete(0, "end")
            self._music_entry.insert(0, music_folder)
        output_folder = self.config.output_folder
        if output_folder:
            self._output_entry.delete(0, "end")
            self._output_entry.insert(0, output_folder)

        last = self.config.last_scan
        if last:
            total = last.get("total_files", 0)
            total_size = last.get("total_size_bytes", 0)
            ts = last.get("timestamp", 0)
            from datetime import datetime
            time_str = datetime.fromtimestamp(ts / 1000).strftime("%m-%d %H:%M") if ts else "-"
            self._total_label.configure(text=f"总文件数\n{total}")
            self._size_label.configure(text=f"总大小\n{format_size(total_size)}")
            self._last_scan_label.configure(text=f"上次扫描\n{time_str}")

    def _on_scan_error(self, error: str) -> None:
        self._scanning = False
        self._progress.stop()
        self._progress.grid_forget()
        self._scan_btn.configure(state="normal", text="开始扫描")
        self._status_label.configure(text=f"扫描失败: {error}")

    def _export_signature(self) -> None:
        if not self.scan_result:
            self._status_label.configure(text="没有可导出的扫描结果")
            return
        output_dir = Path(self.config.output_folder)
        sig_path = output_dir / "pc_signature.json"
        try:
            save_signature(self.scan_result, sig_path)
            self._status_label.configure(text=f"签名文件已导出: {sig_path}")
        except (OSError, ValueError) as e:
            self._status_label.configure(text=f"导出失败: {e}")

    def _import_signature(self) -> None:
        file_path = filedialog.askopenfilename(
            title="导入特征文件",
            filetypes=[("JSON 文件", "*.json"), ("所有文件", "*.*")],
        )
        if not file_path:
            return

        try:
            imported = load_signature(Path(file_path))
            output_dir = Path(self.config.output_folder)
            output_dir.mkdir(parents=True, exist_ok=True)
            total_files = imported.get("scan_summary", {}).get("total_files", len(imported.get("files", [])))

            # 如果已有当前扫描结果，立即执行差异比较
            if self.scan_result:
                try:
                    self.diff_report = compare_signatures(self.scan_result, imported)
                    if self.diff_report:
                        logger.info("导入后差异比较：新增=%d, 更新=%d, 删除=%d, 未变=%d",
                                   len(self.diff_report.added), len(self.diff_report.updated),
                                   len(self.diff_report.removed), self.diff_report.unchanged)
                except (KeyError, TypeError, ValueError) as e:
                    logger.warning("导入后差异比较失败: %s", e)
                    self.diff_report = None
            else:
                # 没有扫描结果时，导入作为当前结果
                self.scan_result = imported

            self._status_label.configure(text=f"导入成功：{total_files} 首歌曲")
            self._export_btn.configure(state="normal")
        except (OSError, ValueError, FileNotFoundError) as e:
            self._status_label.configure(text=f"导入失败: {e}")

    def on_tab_activated(self) -> None:
        self._refresh_state()