"""差异比较引擎 —— 比较两个特征文件，分类展示变更。"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from services.signature import signature_to_hashmap


@dataclass
class DiffReport:
    added: list[dict[str, Any]] = field(default_factory=list)
    removed: list[dict[str, Any]] = field(default_factory=list)
    updated: list[dict[str, Any]] = field(default_factory=list)
    unchanged: int = 0

    @property
    def has_changes(self) -> bool:
        return bool(self.added or self.removed or self.updated)

    @property
    def total_changes(self) -> int:
        return len(self.added) + len(self.removed) + len(self.updated)


def compare_signatures(
    pc_signature: dict[str, Any],
    local_signature: dict[str, Any],
) -> DiffReport:
    pc_map = signature_to_hashmap(pc_signature)
    local_map = signature_to_hashmap(local_signature)

    report = DiffReport()

    for path, entry in pc_map.items():
        if path not in local_map:
            report.added.append(entry)
        elif entry.get("file_size") != local_map[path].get("file_size"):
            report.updated.append(entry)
        else:
            report.unchanged += 1

    for path in local_map:
        if path not in pc_map:
            report.removed.append(local_map[path])

    return report