"""预留扩展接口 —— 局域网同步传输抽象基类。

定义中立、双向、可扩展的传输通道能力接口，供后续阶段（二维码配对、
局域网文件传输等）通过子类化实现。当前提供空实现 `NoopTransport` 作为
「未启用 / 手动拷贝」的兜底实现，保证程序在无网络通道时可正常运行。
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class DeviceInfo:
    """设备元信息，用于双端握手时交换身份与协议版本。

    Attributes:
        endpoint_type: 端点类型标识，如 ``"pc"`` / ``"phone"``。
        name: 设备可读名称。
        version: 应用版本号字符串。
        protocol_version: 传输协议版本号整数，用于兼容性校验。
        peer_id: 本端唯一标识，后续会话与差异同步时用于识别对端。
    """

    endpoint_type: str
    name: str
    version: str
    protocol_version: int
    peer_id: str

    def to_dict(self) -> dict[str, object]:
        """序列化为握手 JSON 使用的字典结构。"""
        return {
            "endpoint_type": self.endpoint_type,
            "name": self.name,
            "version": self.version,
            "protocol_version": self.protocol_version,
            "peer_id": self.peer_id,
        }


@dataclass(frozen=True)
class PairingCode:
    """配对信息，承载连接目标与一次性校验令牌。

    Attributes:
        url: 完整配对地址，如 ``http://<ip>:<port>/pair?token=<rand>``。
        token: 一次性配对令牌，过期或被消费后失效。
        expires_at: 令牌过期时间（Unix 秒时间戳）。
    """

    url: str
    token: str
    expires_at: float


class SyncTransport(ABC):
    """局域网同步传输抽象接口。

    以中立的能力语义描述传输通道，避免将具体技术（HTTP 服务端、UDP 广播
    等）绑定进接口，使发现/配对与传输解耦，便于后续蓝牙 / USB / 云盘等
    通道实现同一接口而无需改动上层调用方。

    子类应在启动后持有本端会话状态，并在停止时正确释放端口与资源。
    """

    @abstractmethod
    def start(self, host: str, port: int) -> None:
        """启动某通道的会话服务。

        Args:
            host: 监听地址（如 ``0.0.0.0`` 或具体 IP）。
            port: 监听端口。
        """

    @abstractmethod
    def stop(self) -> None:
        """停止会话服务并释放资源。"""

    @abstractmethod
    def get_device_info(self) -> DeviceInfo:
        """返回本端设备元信息，供握手交换。"""

    @abstractmethod
    def create_pairing(self) -> PairingCode:
        """生成配对信息（含连接 URL 与一次性 token）。"""


class NoopTransport(SyncTransport):
    """空操作传输实现 —— 所有方法均为空操作。

    作为「未启用 / 手动拷贝」的兜底实现：程序默认使用此实例，保证在无网络
    通道或未开启连接功能时，调用方不会因抽象接口未实现而报错。
    """

    def start(self, host: str, port: int) -> None:
        pass

    def stop(self) -> None:
        pass

    def get_device_info(self) -> DeviceInfo:
        # 空实现返回中立占位信息，字段值无业务含义，仅为满足接口契约。
        return DeviceInfo(
            endpoint_type="none",
            name="none",
            version="0.0.0",
            protocol_version=0,
            peer_id="",
        )

    def create_pairing(self) -> PairingCode:
        # 空实现返回空配对信息，token 为空表示无有效配对。
        return PairingCode(url="", token="", expires_at=0.0)