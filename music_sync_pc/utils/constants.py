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

# 局域网配对默认监听端口与传输协议版本（与手机端对齐）
DEFAULT_PAIRING_PORT: int = 45872
TRANSPORT_PROTOCOL_VERSION: int = 1

# gRPC 数据传输服务默认端口（与 HTTP 配对端口相邻，便于防火墙一并放行）
DEFAULT_GRPC_PORT: int = 45873

# gRPC 文件传输分块大小（字节）：256KB，远小于 gRPC 默认 4MB 消息上限，兼顾吞吐与内存
GRPC_TRANSFER_CHUNK_SIZE: int = 256 * 1024

# gRPC 服务工作线程数：局域网单手机同步场景，少量线程即可承载双向流
GRPC_MAX_WORKERS: int = 8

# 上传过程中的临时文件后缀：未接收完成的文件以该后缀落盘，避免被扫描进音乐库
GRPC_UPLOAD_PART_SUFFIX: str = ".musicsync-part"

# 差异判定维度 id（与手机端 constants.dart 保持一致，供配置与 diff 结果内部使用）
DIFF_DIM_CONTENT_HASH = "content_hash"  # 内容哈希：可选维度，双侧签名均含有效哈希才参与该文件对判定
DIFF_DIM_FILE_SIZE = "file_size"  # 文件大小：强制参与判定的基准维度，不可取消