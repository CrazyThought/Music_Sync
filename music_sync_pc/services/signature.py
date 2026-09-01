"""特征文件读写与校验。"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger("musicsync")

SUPPORTED_FORMAT_VERSIONS: frozenset[str] = frozenset({"2.0"})


def load_signature(file_path: Path) -> dict[str, Any]:
    if not file_path.exists():
        raise FileNotFoundError(f"特征文件不存在: {file_path}")

    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    validate_signature(data)
    return data


def save_signature(data: dict[str, Any], file_path: Path) -> None:
    validate_signature(data)
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    logger.info("特征文件已保存: %s", file_path)


def validate_signature(data: dict[str, Any]) -> None:
    fmt = data.get("format_version", "")
    if fmt not in SUPPORTED_FORMAT_VERSIONS:
        raise ValueError(f"不支持的特征文件版本: {fmt}")

    algo = data.get("fingerprint_algorithms", {}).get("content", "")
    if algo not in ("xxh64", "xxh3_64", "none"):
        raise ValueError(f"不支持的哈希算法: {algo}")

    if "files" not in data or not isinstance(data["files"], list):
        raise ValueError("特征文件缺少 files 字段或格式不正确")


def signature_to_hashmap(signature: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for entry in signature.get("files", []):
        path = entry.get("relative_path", "")
        if path:
            result[path] = entry
    return result