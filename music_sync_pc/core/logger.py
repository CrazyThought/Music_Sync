"""日志管理器 —— 文件轮转 + 控制台输出 + 内存环形缓冲。"""

from __future__ import annotations

import logging
import sys
import threading
import time
from collections import deque
from logging.handlers import RotatingFileHandler
from pathlib import Path

from utils.constants import DEFAULT_LOG_DIR

MAX_LOG_SIZE: int = 5 * 1024 * 1024
BACKUP_COUNT: int = 3

_RING_BUFFER_SIZE: int = 1000
_RING_TIME_FORMAT: str = "%H:%M:%S"


class RingLogHandler(logging.Handler):
    """基于内存环形缓冲的日志处理器，供 UI 实时展示与回看调试日志。

    内部使用 collections.deque(maxlen=...) 保存最近最多 1000 条结构化日志
    条目（FIFO 淘汰最旧条目），并通过 threading.Lock 保证多线程环境下
    的读写安全。默认接收 DEBUG 及以上级别的全部日志。

    Attributes:
        _buffer: 保存结构化日志条目的环形缓冲。
        _lock: 保护环形缓冲读写的线程锁。
    """

    def __init__(self, capacity: int = _RING_BUFFER_SIZE) -> None:
        """初始化环形缓冲日志处理器。

        Args:
            capacity: 环形缓冲容量上限，超过后自动淘汰最旧条目。
        """
        super().__init__(level=logging.DEBUG)
        self._buffer: deque[dict[str, str]] = deque(maxlen=capacity)
        self._lock = threading.Lock()

    def emit(self, record: logging.LogRecord) -> None:
        """将日志记录转成结构化条目写入环形缓冲。

        以日志产生时刻（record.created）格式化出 HH:MM:SS 时间字符串，
        与消息一起组成 {"time", "level", "message"} 条目入队；入队过程
        任何异常都交给 handleError 兜底处理，绝不向上抛出。

        Args:
            record: 待处理的日志记录对象。
        """
        try:
            entry: dict[str, str] = {
                "time": time.strftime(_RING_TIME_FORMAT, time.localtime(record.created)),
                "level": record.levelname,
                "message": record.getMessage(),
            }
            with self._lock:
                self._buffer.append(entry)
        except Exception:
            self.handleError(record)

    def snapshot(self) -> list[dict[str, str]]:
        """返回环形缓冲中全部条目的有序副本（线程安全）。

        Returns:
            按写入顺序排列的结构化日志条目列表；缓冲为空时返回空列表。
        """
        with self._lock:
            return list(self._buffer)

    def clear(self) -> None:
        """清空环形缓冲中的全部日志条目。"""
        with self._lock:
            self._buffer.clear()


# 全局唯一的环形缓冲 handler 实例，setup_logger 挂载成功后赋值
_ring_handler: RingLogHandler | None = None


def setup_logger(log_dir: Path | None = None) -> logging.Logger:
    """初始化全局 logger 及其处理器（文件轮转 + 控制台 + 环形缓冲）。

    logger 全局级别提升为 DEBUG（控制台 handler 仍为 INFO 不刷屏），
    使环形缓冲自启动起即可采集 DEBUG 及以上级别的完整日志，不依赖
    调试日志开关。handler 守卫保证本函数重复调用不会重复挂载。

    Args:
        log_dir: 日志输出目录；None 时使用默认目录。

    Returns:
        配置完成的全局 logger 实例。
    """
    global _ring_handler
    log_dir = log_dir or DEFAULT_LOG_DIR
    log_dir.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger("musicsync")
    logger.setLevel(logging.DEBUG)

    if logger.handlers:
        return logger

    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    file_handler = RotatingFileHandler(
        log_dir / "musicsync.log",
        maxBytes=MAX_LOG_SIZE,
        backupCount=BACKUP_COUNT,
        encoding="utf-8",
    )
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setLevel(logging.INFO)
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    _ring_handler = RingLogHandler()
    _ring_handler.setFormatter(formatter)
    logger.addHandler(_ring_handler)

    return logger


def get_logger() -> logging.Logger:
    return logging.getLogger("musicsync")


def ring_snapshot() -> list[dict[str, str]]:
    """获取全局环形缓冲日志条目的有序副本。

    setup_logger 尚未运行时安全返回空列表，供 UI 任意时刻调用。

    Returns:
        按写入顺序排列的结构化日志条目列表；缓冲为空或未初始化时为空列表。
    """
    handler = _ring_handler
    if handler is None:
        return []
    return handler.snapshot()


def ring_clear() -> None:
    """清空全局环形缓冲中的全部日志条目。

    setup_logger 尚未运行时为空操作，供 UI 任意时刻安全调用。
    """
    handler = _ring_handler
    if handler is None:
        return
    handler.clear()
