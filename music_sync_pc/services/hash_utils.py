"""文件哈希工具 —— xxHash-64，大文件分块策略。"""

from __future__ import annotations

import xxhash
from pathlib import Path


def compute_xxhash64(file_path: Path) -> str:
    h = xxhash.xxh64()
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(8192)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def compute_chunked_hash(
    file_path: Path,
    file_size: int,
    chunk_size: int = 128 * 1024,
) -> str:
    """大文件分块哈希：首尾各 chunk_size 字节组合计算。"""
    if file_size <= chunk_size * 2:
        return compute_xxhash64(file_path)

    h = xxhash.xxh64()
    with open(file_path, "rb") as f:
        h.update(f.read(chunk_size))
        f.seek(max(0, file_size - chunk_size))
        h.update(f.read(chunk_size))
    return h.hexdigest()