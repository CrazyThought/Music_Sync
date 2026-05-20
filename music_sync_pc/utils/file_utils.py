"""文件系统工具函数。"""

from __future__ import annotations

import os
from pathlib import Path

from utils.constants import AUDIO_EXTENSIONS


def is_audio_file(file_path: Path) -> bool:
    return file_path.suffix.lower() in AUDIO_EXTENSIONS


def safe_get_size(file_path: Path) -> int:
    try:
        return file_path.stat().st_size
    except OSError:
        return 0


def safe_get_mtime(file_path: Path) -> int:
    try:
        return int(file_path.stat().st_mtime * 1000)
    except OSError:
        return 0


def format_size(bytes_count: int) -> str:
    if bytes_count < 1024:
        return f"{bytes_count} B"
    elif bytes_count < 1024 * 1024:
        return f"{bytes_count / 1024:.1f} KB"
    elif bytes_count < 1024 * 1024 * 1024:
        return f"{bytes_count / (1024 * 1024):.1f} MB"
    else:
        return f"{bytes_count / (1024 * 1024 * 1024):.2f} GB"


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)