"""常量定义模块。"""

from __future__ import annotations

from pathlib import Path

APP_NAME = "MusicSync"
APP_VERSION = "1.0.0"
SIGNATURE_FORMAT_VERSION = "2.0"

AUDIO_EXTENSIONS: frozenset[str] = frozenset({
    ".mp3", ".flac", ".wav", ".m4a", ".ogg",
    ".wma", ".aac", ".opus", ".ape", ".wv",
})

LARGE_FILE_THRESHOLD_BYTES: int = 100 * 1024 * 1024
CHUNK_HASH_SIZE_BYTES: int = 128 * 1024

DEFAULT_MAX_WORKERS: int = 4
DEFAULT_OUTPUT_DIR: Path = Path("./output")
DEFAULT_LOG_DIR: Path = Path("./logs")
CONFIG_FILE_NAME: str = "config.json"
SIGNATURE_FILE_NAME: str = "pc_signature.json"