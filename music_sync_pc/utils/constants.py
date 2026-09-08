"""常量定义模块。"""

from __future__ import annotations

from pathlib import Path

APP_NAME = "MusicSync"
APP_VERSION = "1.1.1"
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

# 差异判定维度 id（与手机端 constants.dart 保持一致，供配置与 diff 结果内部使用）
DIFF_DIM_CONTENT_HASH = "content_hash"  # 内容哈希：可选维度，双侧签名均含有效哈希才参与该文件对判定
DIFF_DIM_FILE_SIZE = "file_size"  # 文件大小：强制参与判定的基准维度，不可取消