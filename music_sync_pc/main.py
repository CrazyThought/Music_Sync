"""MusicSync PC 端 —— 程序入口，单实例检查，异常全局捕获。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from core.config import ConfigManager
from core.logger import setup_logger, get_logger

_SINGLE_INSTANCE_LOCK: Path = Path.home() / ".musicsync" / ".lock"


def _acquire_lock() -> bool:
    _SINGLE_INSTANCE_LOCK.parent.mkdir(parents=True, exist_ok=True)
    try:
        if _SINGLE_INSTANCE_LOCK.exists():
            try:
                pid = int(_SINGLE_INSTANCE_LOCK.read_text().strip())
                import os
                os.kill(pid, 0)
                return False
            except (OSError, ValueError):
                pass
        _SINGLE_INSTANCE_LOCK.write_text(str(__import__("os").getpid()))
        return True
    except OSError:
        return True


def _release_lock() -> None:
    try:
        _SINGLE_INSTANCE_LOCK.unlink(missing_ok=True)
    except OSError:
        pass


def main() -> None:
    setup_logger()
    logger = get_logger()
    logger.info("MusicSync PC 端 v1.0.0 启动")

    if not _acquire_lock():
        logger.warning("检测到已有实例正在运行，本次启动取消")
        print("MusicSync 已在运行中。如需重启，请先关闭已有窗口。")
        return

    try:
        config = ConfigManager()

        from app import App
        app = App(config)
        app.mainloop()
    except SystemExit:
        pass
    except KeyboardInterrupt:
        logger.info("用户中断程序")
    except Exception:
        logger.exception("程序异常退出")
    finally:
        _release_lock()


if __name__ == "__main__":
    main()