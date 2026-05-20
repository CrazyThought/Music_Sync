"""配置管理器 —— JSON 持久化，多层降级容错。"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from utils.constants import (
    APP_NAME,
    APP_VERSION,
    CONFIG_FILE_NAME,
    DEFAULT_MAX_WORKERS,
    DEFAULT_OUTPUT_DIR,
    LARGE_FILE_THRESHOLD_BYTES,
    CHUNK_HASH_SIZE_BYTES,
)

_DEFAULT_CONFIG: dict[str, Any] = {
    "version": APP_VERSION,
    "music_folder": "",
    "output_folder": str(DEFAULT_OUTPUT_DIR),
    "scan_settings": {
        "max_workers": DEFAULT_MAX_WORKERS,
        "extensions": ["mp3", "flac", "wav", "m4a", "ogg", "wma", "aac", "opus", "ape", "wv"],
        "large_file_threshold_mb": LARGE_FILE_THRESHOLD_BYTES // (1024 * 1024),
        "chunk_hash_size_kb": CHUNK_HASH_SIZE_BYTES // 1024,
    },
    "appearance": {
        "theme": "dark",
        "language": "zh",
    },
    "last_scan": {},
}


class ConfigManager:
    """应用配置管理器。

    加载优先级：
    1. exe 同目录下的 config.json
    2. 用户目录下的 .musicsync/config.json
    3. 内置默认值
    """

    def __init__(self) -> None:
        self._data: dict[str, Any] = self._load_with_fallback()

    def _config_paths(self) -> list[Path]:
        exe_dir = Path(sys.argv[0]).resolve().parent if hasattr(sys, "argv") else Path.cwd()
        return [
            exe_dir / CONFIG_FILE_NAME,
            Path.home() / f".{APP_NAME.lower()}" / CONFIG_FILE_NAME,
        ]

    def _load_with_fallback(self) -> dict[str, Any]:
        for path in self._config_paths():
            try:
                if path.exists():
                    with open(path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    if isinstance(data, dict):
                        return self._merge_defaults(data)
            except Exception:
                continue
        return dict(_DEFAULT_CONFIG)

    def _merge_defaults(self, loaded: dict[str, Any]) -> dict[str, Any]:
        result = dict(_DEFAULT_CONFIG)
        result.update({k: v for k, v in loaded.items() if k in result})
        return result

    @property
    def music_folder(self) -> str:
        return str(self._data.get("music_folder", ""))

    @music_folder.setter
    def music_folder(self, value: str) -> None:
        self._data["music_folder"] = value
        self.save()

    @property
    def output_folder(self) -> str:
        return str(self._data.get("output_folder", str(DEFAULT_OUTPUT_DIR)))

    @output_folder.setter
    def output_folder(self, value: str) -> None:
        self._data["output_folder"] = value
        self.save()

    @property
    def max_workers(self) -> int:
        return int(self._data.get("scan_settings", {}).get("max_workers", DEFAULT_MAX_WORKERS))

    @max_workers.setter
    def max_workers(self, value: int) -> None:
        self._data.setdefault("scan_settings", {})["max_workers"] = value
        self.save()

    @property
    def extensions(self) -> list[str]:
        return list(self._data.get("scan_settings", {}).get("extensions", []))

    @extensions.setter
    def extensions(self, value: list[str]) -> None:
        self._data.setdefault("scan_settings", {})["extensions"] = value
        self.save()

    @property
    def theme(self) -> str:
        return str(self._data.get("appearance", {}).get("theme", "dark"))

    @theme.setter
    def theme(self, value: str) -> None:
        self._data.setdefault("appearance", {})["theme"] = value
        self.save()

    @property
    def last_scan(self) -> dict[str, Any]:
        return dict(self._data.get("last_scan", {}))

    @last_scan.setter
    def last_scan(self, value: dict[str, Any]) -> None:
        self._data["last_scan"] = value
        self.save()

    @property
    def large_file_threshold(self) -> int:
        mb = self._data.get("scan_settings", {}).get("large_file_threshold_mb", 100)
        return int(mb) * 1024 * 1024

    @property
    def chunk_hash_size(self) -> int:
        kb = self._data.get("scan_settings", {}).get("chunk_hash_size_kb", 128)
        return int(kb) * 1024

    @property
    def raw(self) -> dict[str, Any]:
        return dict(self._data)

    def save(self) -> None:
        config_path = self._config_paths()[0]
        config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2, ensure_ascii=False)

    def set_large_file_threshold_mb(self, value: int) -> None:
        self._data.setdefault("scan_settings", {})["large_file_threshold_mb"] = value
        self.save()

    def reset(self) -> None:
        self._data = dict(_DEFAULT_CONFIG)
        self.save()