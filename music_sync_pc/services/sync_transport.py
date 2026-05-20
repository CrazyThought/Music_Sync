"""预留扩展接口 —— 局域网同步传输抽象基类。

当前阶段返回空实现，后续阶段通过子类化实现局域网文件传输。
"""

from __future__ import annotations

from abc import ABC, abstractmethod


class SyncTransport(ABC):
    """局域网同步传输抽象接口。

    预留用于后续阶段的局域网发现、签名传输和文件下载功能。
    当前所有方法均为空实现，调用时抛出 NotImplementedError。
    """

    @abstractmethod
    def start_server(self, host: str, port: int) -> None:
        """启动 HTTP 文件服务器。"""

    @abstractmethod
    def stop_server(self) -> None:
        """停止 HTTP 文件服务器。"""

    @abstractmethod
    def get_peers(self) -> list[str]:
        """通过 UDP 广播发现局域网内的对等设备。"""


class NoopTransport(SyncTransport):
    """空操作传输实现 —— 所有方法均为空操作。"""

    def start_server(self, host: str, port: int) -> None:
        pass

    def stop_server(self) -> None:
        pass

    def get_peers(self) -> list[str]:
        return []