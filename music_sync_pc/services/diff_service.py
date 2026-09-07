"""差异比较引擎 —— 比较两个特征文件，分类展示变更。"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

from services.signature import signature_to_hashmap
from utils.constants import DIFF_DIM_CONTENT_HASH, DIFF_DIM_FILE_SIZE


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


def _has_valid_dim(entry: dict[str, Any], dim: str) -> bool:
    """判断单条文件记录在可选维度上是否具备有效值（供维度放行规则使用）。"""
    if dim == DIFF_DIM_CONTENT_HASH:
        # 哈希有效：内容哈希非空 且 算法标识非 none/缺失（未开启哈希视为无有效值）
        return bool(entry.get("content_hash")) and entry.get("content_hash_algo") not in (None, "none")
    return entry.get(dim) is not None


def compare_signatures(
    pc_signature: dict[str, Any],
    local_signature: dict[str, Any],
    judgment_dims: Sequence[str] = (),
) -> DiffReport:
    """比较 PC 与本地签名，返回差异报告。

    Args:
        pc_signature: PC 端签名数据。
        local_signature: 本地/手机端签名数据。
        judgment_dims: 用户额外启用的判定维度 id（不含强制维度 file_size）。
            默认空，行为与旧版仅按 file_size 判定一致。

    Returns:
        DiffReport，新增/更新/可删除/未变四类结果。
    """
    pc_map = signature_to_hashmap(pc_signature)
    local_map = signature_to_hashmap(local_signature)

    report = DiffReport()

    for path, entry in pc_map.items():
        local_entry = local_map.get(path)
        if local_entry is None:
            # 仅 PC 端存在该路径 → 新增
            report.added.append(entry)
            continue

        # 参与判定维度集合：file_size 恒参与；可选维度仅当两侧均有效才参与，
        # 单侧缺值（如旧签名/未开哈希）自动放行，避免误判"更新"
        active_dims: list[str] = [DIFF_DIM_FILE_SIZE]
        for dim in judgment_dims:
            if dim == DIFF_DIM_FILE_SIZE:
                continue
            if _has_valid_dim(entry, dim) and _has_valid_dim(local_entry, dim):
                active_dims.append(dim)

        # AND 合并：任一参与维度不一致即"更新"；_diff_dims 按维度 id 列表记录不一致项
        mismatch_dims: list[str] = [
            dim for dim in active_dims if entry.get(dim) != local_entry.get(dim)
        ]
        if mismatch_dims:
            # 浅拷贝原条目并附加内部键 _diff_dims（供 UI 展示差异依据），
            # 避免直接修改签名对象而污染签名文件数据
            updated_entry = dict(entry)
            updated_entry["_diff_dims"] = mismatch_dims
            report.updated.append(updated_entry)
        else:
            report.unchanged += 1

    for path in local_map:
        if path not in pc_map:
            # 仅本地端存在该路径 → 可删除
            report.removed.append(local_map[path])

    return report