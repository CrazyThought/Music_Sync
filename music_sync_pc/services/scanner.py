"""文件扫描引擎 —— 递归遍历音乐目录，收集元数据和哈希。"""

from __future__ import annotations

import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

from services.audio_meta import extract_audio_meta
from services.hash_utils import compute_xxhash64, compute_chunked_hash
from utils.constants import AUDIO_EXTENSIONS, LARGE_FILE_THRESHOLD_BYTES
from utils.file_utils import safe_get_size, safe_get_mtime

logger = logging.getLogger("musicsync")


class MusicScanner:
    """音乐文件夹扫描器。

    负责递归遍历指定目录，收集所有符合扩展名条件的音频文件，
    并提取文件元数据和内容哈希。

    Attributes:
        root_path: 扫描的根目录路径。
        max_workers: 并行处理的线程数。
        extensions: 扫描的音频文件扩展名集合。
        chunk_hash_size: 大文件分块哈希的块大小（字节）。
        large_file_threshold: 触发分块哈希的文件大小阈值（字节）。
    """

    def __init__(
        self,
        root_path: Path,
        max_workers: int = 4,
        extensions: frozenset[str] | None = None,
        chunk_hash_size: int = 128 * 1024,
        large_file_threshold: int = LARGE_FILE_THRESHOLD_BYTES,
    ) -> None:
        self.root_path = root_path
        self.max_workers = max_workers
        self.extensions = extensions or AUDIO_EXTENSIONS
        self.chunk_hash_size = chunk_hash_size
        self.large_file_threshold = large_file_threshold

    def scan(self, previous_signature: dict[str, Any] | None = None) -> dict[str, Any]:
        """执行扫描并返回签名数据。

        递归遍历 root_path，收集音频文件并计算内容哈希和元数据。
        当提供 previous_signature 时，仅处理变更的文件（增量扫描）。

        Args:
            previous_signature: 上次扫描的签名数据，用于增量过滤。
                None 表示执行全量扫描。

        Returns:
            符合 SIGNATURE_SPEC v2.0 的签名字典。

        Raises:
            PermissionError: 当无权限读取目录时。
        """
        start_time = time.time()

        all_files = self._collect_files()
        logger.info("发现 %d 个音频文件", len(all_files))

        changed = self._quick_filter(all_files, previous_signature)
        total_skipped = len(all_files) - len(changed)
        if total_skipped > 0:
            logger.info("快速过滤跳过 %d 个未变化文件，需处理 %d 个", total_skipped, len(changed))

        results: list[dict[str, Any]] = []
        if previous_signature and total_skipped > 0:
            unchanged = self._collect_unchanged(previous_signature, changed)
            results.extend(unchanged)

        if changed:
            with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
                futures = {
                    executor.submit(self._process_file, f): f
                    for f in changed
                }
                for future in as_completed(futures):
                    try:
                        results.append(future.result())
                    except Exception:
                        logger.exception("处理文件失败: %s", futures[future])

        results.sort(key=lambda x: x["relative_path"])
        scan_duration_ms = int((time.time() - start_time) * 1000)

        return self._build_signature(results, scan_duration_ms)

    def _collect_files(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for file_path in self.root_path.rglob("*"):
            if not file_path.is_file():
                continue
            if file_path.suffix.lower() not in self.extensions:
                continue
            try:
                relative = str(file_path.relative_to(self.root_path)).replace("\\", "/")
            except ValueError:
                continue
            result.append({
                "relative_path": relative,
                "file_size": safe_get_size(file_path),
                "modified_at": safe_get_mtime(file_path),
                "_abs_path": str(file_path),
            })
        return result

    def _quick_filter(
        self,
        current: list[dict[str, Any]],
        previous: dict[str, Any] | None,
    ) -> list[dict[str, Any]]:
        if not previous:
            return current

        snap: dict[str, tuple[int, int]] = {}
        for f in previous.get("files", []):
            key = f["relative_path"]
            snap[key] = (f.get("file_size", 0), f.get("modified_at", 0))

        result: list[dict[str, Any]] = []
        for entry in current:
            key = entry["relative_path"]
            cached = snap.get(key)
            if cached is None:
                result.append(entry)
            elif entry["file_size"] != cached[0] or entry["modified_at"] != cached[1]:
                result.append(entry)
        return result

    def _collect_unchanged(
        self,
        previous: dict[str, Any],
        changed: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        changed_keys = {f["relative_path"] for f in changed}
        return [
            {k: v for k, v in f.items() if not k.startswith("_")}
            for f in previous.get("files", [])
            if f["relative_path"] not in changed_keys
        ]

    def _process_file(self, file_info: dict[str, Any]) -> dict[str, Any]:
        abs_path = Path(file_info.pop("_abs_path"))
        file_size = file_info["file_size"]

        if file_size >= self.large_file_threshold:
            content_hash = compute_chunked_hash(abs_path, file_size, self.chunk_hash_size)
        else:
            content_hash = compute_xxhash64(abs_path)

        meta = extract_audio_meta(abs_path)

        return {
            **file_info,
            "content_hash": content_hash,
            "content_hash_algo": "xxh64",
            "audio_meta": meta,
            "audio_fingerprint": None,
        }

    def _build_signature(
        self,
        files: list[dict[str, Any]],
        scan_duration_ms: int,
    ) -> dict[str, Any]:
        total_size = sum(f["file_size"] for f in files)
        return {
            "format_version": "2.0",
            "generated_by": "MusicSync/PC/1.0.0",
            "generated_at": int(time.time() * 1000),
            "scan_root": str(self.root_path),
            "scan_summary": {
                "total_files": len(files),
                "total_size_bytes": total_size,
                "scan_duration_ms": scan_duration_ms,
            },
            "files": files,
            "fingerprint_algorithms": {
                "content": "xxh64",
                "audio": "none",
            },
        }