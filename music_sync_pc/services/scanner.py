"""文件扫描引擎 —— 递归遍历音乐目录，收集元数据和哈希。"""

from __future__ import annotations

import functools
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

    def scan(
        self,
        previous_signature: dict[str, Any] | None = None,
        compute_hash: bool = True,
    ) -> dict[str, Any]:
        """执行扫描并返回签名数据。

        递归遍历 root_path，收集音频文件并计算内容哈希和元数据。
        当提供 previous_signature 时，仅处理变更的文件（增量扫描）。

        Args:
            previous_signature: 上次扫描的签名数据，用于增量过滤。
                None 表示执行全量扫描。
            compute_hash: 是否计算文件内容哈希。为 False 时跳过一切内容哈希
                读取（含大文件分块哈希），文件条目输出 content_hash=''、
                content_hash_algo='none'，顶层 fingerprint_algorithms.content='none'。

        Returns:
            符合 SIGNATURE_SPEC v2.0 的签名字典。

        Raises:
            PermissionError: 当无权限读取目录时。
        """
        start_time = time.time()
        logger.info("扫描开始: %s (计算哈希=%s)", self.root_path, compute_hash)
        if not compute_hash:
            logger.info("哈希计算已关闭，扫描跳过内容哈希读取")

        all_files = self._collect_files()
        logger.info("发现 %d 个音频文件", len(all_files))

        changed = self._quick_filter(all_files, previous_signature, compute_hash)
        total_skipped = len(all_files) - len(changed)
        if total_skipped > 0:
            logger.info("快速过滤跳过 %d 个未变化文件，需处理 %d 个", total_skipped, len(changed))

        results: list[dict[str, Any]] = []
        if previous_signature and total_skipped > 0:
            unchanged = self._collect_unchanged(previous_signature, changed, compute_hash)
            results.extend(unchanged)

        if changed:
            process_file = functools.partial(self._process_file, compute_hash=compute_hash)
            with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
                futures = {
                    executor.submit(process_file, f): f
                    for f in changed
                }
                for future in as_completed(futures):
                    try:
                        results.append(future.result())
                    except Exception:
                        logger.exception("处理文件失败: %s", futures[future])

        results.sort(key=lambda x: x["relative_path"])
        scan_duration_ms = int((time.time() - start_time) * 1000)
        logger.info(
            "扫描完成: 共 %d 个文件, 总大小 %d 字节, 耗时 %d 毫秒 (计算哈希=%s)",
            len(results),
            sum(f["file_size"] for f in results),
            scan_duration_ms,
            compute_hash,
        )

        return self._build_signature(results, scan_duration_ms, compute_hash)

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
        compute_hash: bool,
    ) -> list[dict[str, Any]]:
        """快速过滤出需要重新处理的文件。

        默认以 (file_size, modified_at) 判定文件是否变更；当 compute_hash 为
        True 且缓存条目哈希无效（content_hash_algo 为 None/'none' 或
        content_hash 为空）时，视为变更以补算哈希，保证开关切换后签名自洽。
        compute_hash 为 False 时保持原逻辑（仅大小/时间判定）。

        Args:
            current: 本次扫描到的文件列表。
            previous: 上次扫描的签名数据。None 表示全量扫描，返回全部 current。
            compute_hash: 是否计算内容哈希。

        Returns:
            需要重新处理的文件列表。
        """
        if not previous:
            return current

        snap: dict[str, dict[str, Any]] = {}
        for f in previous.get("files", []):
            snap[f["relative_path"]] = f

        result: list[dict[str, Any]] = []
        for entry in current:
            key = entry["relative_path"]
            cached = snap.get(key)
            if cached is None:
                result.append(entry)
            elif (
                entry["file_size"] != cached.get("file_size", 0)
                or entry["modified_at"] != cached.get("modified_at", 0)
            ):
                result.append(entry)
            elif compute_hash and self._cache_hash_invalid(cached):
                result.append(entry)
        return result

    @staticmethod
    def _cache_hash_invalid(cached: dict[str, Any]) -> bool:
        """判断缓存文件条目的内容哈希是否无效。

        content_hash_algo 为 None/'none' 或 content_hash 为空时视为无效，
        表示该缓存未携带可用哈希，需在开启哈希计算时重新补算。
        """
        algo = cached.get("content_hash_algo")
        return algo is None or algo == "none" or not cached.get("content_hash")

    def _collect_unchanged(
        self,
        previous: dict[str, Any],
        changed: list[dict[str, Any]],
        compute_hash: bool,
    ) -> list[dict[str, Any]]:
        """从上次签名中收集未变更的文件条目（增量扫描复用缓存）。

        compute_hash 为 False 时将缓存的旧条目归一化为无哈希字段
        （content_hash=''、content_hash_algo='none'），避免混合哈希/无哈希输出。

        Args:
            previous: 上次扫描的签名数据。
            changed: 本次需要重新处理的文件列表。
            compute_hash: 是否计算内容哈希。

        Returns:
            可直接用于签名的未变更文件条目列表。
        """
        changed_keys = {f["relative_path"] for f in changed}
        result: list[dict[str, Any]] = []
        for f in previous.get("files", []):
            if f["relative_path"] in changed_keys:
                continue
            entry = {k: v for k, v in f.items() if not k.startswith("_")}
            if not compute_hash:
                entry["content_hash"] = ""
                entry["content_hash_algo"] = "none"
            result.append(entry)
        return result

    def _process_file(self, file_info: dict[str, Any], compute_hash: bool) -> dict[str, Any]:
        """处理单个音频文件，提取元数据并按开关计算内容哈希。

        compute_hash 为 False 时不读取文件内容做哈希（含大文件分块哈希），
        输出 content_hash=''、content_hash_algo='none'；audio_meta 与
        audio_fingerprint=None 在两种模式下均照常输出。

        Args:
            file_info: 含 _abs_path 的文件信息字典。
            compute_hash: 是否计算内容哈希。

        Returns:
            合并哈希与元数据后的文件条目字典。
        """
        abs_path = Path(file_info.pop("_abs_path"))
        file_size = file_info["file_size"]

        if compute_hash:
            if file_size >= self.large_file_threshold:
                content_hash = compute_chunked_hash(abs_path, file_size, self.chunk_hash_size)
            else:
                content_hash = compute_xxhash64(abs_path)
            content_hash_algo = "xxh3_64"
        else:
            content_hash = ""
            content_hash_algo = "none"

        meta = extract_audio_meta(abs_path)

        return {
            **file_info,
            "content_hash": content_hash,
            "content_hash_algo": content_hash_algo,
            "audio_meta": meta,
            "audio_fingerprint": None,
        }

    def _build_signature(
        self,
        files: list[dict[str, Any]],
        scan_duration_ms: int,
        compute_hash: bool,
    ) -> dict[str, Any]:
        """组装符合 SIGNATURE_SPEC v2.0 的签名字典。

        Args:
            files: 文件条目列表。
            scan_duration_ms: 本次扫描耗时（毫秒）。
            compute_hash: 是否计算内容哈希；开启时
                fingerprint_algorithms.content='xxh3_64'，否则为 'none'。

        Returns:
            签名字典。
        """
        total_size = sum(f["file_size"] for f in files)
        content_algo = "xxh3_64" if compute_hash else "none"
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
                "content": content_algo,
                "audio": "none",
            },
        }