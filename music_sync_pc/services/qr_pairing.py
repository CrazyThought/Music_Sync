"""二维码配对传输 —— 基于标准库 HTTP 服务的局域网配对实现。

实现 :class:`SyncTransport` 抽象接口，提供单会话 HTTP 配对服务：
PC 端启动服务并生成携带一次性 token 的二维码，手机端扫码后携带 token
请求 `/pair` 完成握手（交换 ``DeviceInfo``），成功后拒绝后续配对请求。

二维码 URL 形如 ``http://<ip>:<port>/pair?token=<rand>``，token 一次性
且带过期时间，保证局域网内只有扫到当前二维码的方可建立会话。
"""

from __future__ import annotations

import json
import logging
import secrets
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

from services.sync_transport import DeviceInfo, PairingCode, SyncTransport
from utils.constants import (
    APP_VERSION,
    DEFAULT_PAIRING_PORT,
    TRANSPORT_PROTOCOL_VERSION,
)

logger = logging.getLogger("musicsync")

# token 有效期（秒）：超过后即便未被消费也视为过期，需重新生成二维码
_TOKEN_TTL_SECONDS: float = 180.0

# 心跳超时（秒）：配对成功后若连续该时长内未收到手机心跳，则判定手机已断开。
# 允许连续丢失约 3 个 3 秒间隔的心跳，避免瞬时网络抖动误判。
_HEARTBEAT_TIMEOUT_SECONDS: float = 9.0


def render_qr_image(text: str, box_size: int = 10, border: int = 4) -> Any:
    """将文本编码为二维码并渲染成 PIL 图像对象。

    供 UI 层展示用；qrcode 依赖 pillow 图像后端，返回可直接交给
    customtkinter CTkImage 或对话框展示的 PIL.Image 实例。

    Args:
        text: 待编码的二维码内容（这里是配对 URL）。
        box_size: 单个码元像素大小，越大越清晰。
        border: 二维码四周空白边距（码元数量）。

    Returns:
        PIL.Image 对象。
    """
    import qrcode  # 局部导入：仅在需要展示二维码时才引入渲染依赖

    qr = qrcode.QRCode(version=None, box_size=box_size, border=border)
    qr.add_data(text)
    qr.make(fit=True)
    # make_image 返回的是 qrcode.image.pil.PilImage（PIL.Image 的子类），
    # 而 CTkImage 对图片类型做精确 `type is PIL.Image.Image` 判断，子类不通过，
    # 因此调用 get_image() 取回真正的 PIL.Image.Image 实例。
    return qr.make_image(fill_color="black", back_color="white").get_image()


def _get_lan_ip() -> str:
    """获取本机局域网 IP，用于组装二维码 URL。

    通过创建 UDP socket 连接外部地址的方式，让操作系统路由表决定出口
    网卡，从而拿到真实局域网 IP（避免取到回环地址或虚拟网卡地址）。
    无法确定时回退到 127.0.0.1（仅本机可用）。

    Returns:
        本机局域网 IPv4 地址字符串。
    """
    sock: socket.socket | None = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        return str(sock.getsockname()[0])
    except OSError:
        return "127.0.0.1"
    finally:
        if sock is not None:
            sock.close()


class QrPairingTransport(SyncTransport):
    """二维码配对传输实现。

    内部维护一个单会话 HTTP 服务与一次性配对令牌：
    - ``start`` 启动服务并监听指定端口，若端口被占用则自动递增重试；
    - ``create_pairing`` 生成一次性 token 与二维码 URL；
    - 手机端扫码访问 ``/pair?token=...`` 完成握手交换设备信息；
    - 握手成功后拒绝新的配对请求，直到 ``stop`` 释放并重新 ``start``。

    Attributes:
        host: 监听地址。
        port: 实际监听端口（可能与请求端口不同，因端口占用自动递增）。
        _paired: 是否已完成配对握手。
        _token: 当前有效令牌；None 表示暂无配对请求。
        _token_expires_at: 令牌过期时间戳。
        _server: 底层 HTTP 服务实例（启动后非 None）。
        _thread: 服务运行线程。
        _peer_id: 本端唯一标识，用于对端识别。
    """

    def __init__(self) -> None:
        self.host: str = "0.0.0.0"
        self.port: int = DEFAULT_PAIRING_PORT
        self._paired: bool = False
        self._token: str | None = None
        self._token_expires_at: float = 0.0
        self._server: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None
        self._peer_id: str = secrets.token_hex(8)
        self._peer_info: DeviceInfo | None = None
        self._last_seen_at: float = 0.0
        self._lock = threading.Lock()

    # ------------------------------------------------------------------
    # SyncTransport 接口实现
    # ------------------------------------------------------------------
    @property
    def is_paired(self) -> bool:
        """当前会话是否已完成配对握手（供 UI 轮询展示状态）。"""
        with self._lock:
            return self._paired

    def start(self, host: str, port: int) -> None:
        """启动会话服务并监听指定端口，端口占用则自动递增重试。

        Args:
            host: 监听地址。
            port: 期望监听端口。
        """
        self.host = host
        self.port = port
        handler = self._build_handler()
        server = self._bind_server(host, port, handler)
        self._server = server
        self._thread = threading.Thread(
            target=server.serve_forever, name="qr-pairing-server", daemon=True
        )
        self._thread.start()
        logger.info("二维码配对服务已启动: %s:%s", host, self.port)

    def stop(self) -> None:
        """停止会话服务并释放端口与线程资源。"""
        with self._lock:
            self._paired = False
            self._token = None
            self._peer_info = None
            self._last_seen_at = 0.0
        server = self._server
        if server is not None:
            server.shutdown()
            server.server_close()
            self._server = None
        self._thread = None
        logger.info("二维码配对服务已停止")

    def get_device_info(self) -> DeviceInfo:
        """返回本端（PC）设备元信息。"""
        return DeviceInfo(
            endpoint_type="pc",
            name=socket.gethostname(),
            version=APP_VERSION,
            protocol_version=TRANSPORT_PROTOCOL_VERSION,
            peer_id=self._peer_id,
        )

    def get_peer_info(self) -> DeviceInfo | None:
        """返回配对成功的对端设备信息（未配对时返回 None）。

        Returns:
            对端 :class:`DeviceInfo`，未握手成功时为 ``None``。
        """
        with self._lock:
            return self._peer_info

    def is_peer_alive(self) -> bool:
        """判断对端（手机）是否仍在正常维持心跳。

        配对成功后由手机端定时发送心跳刷新 ``_last_seen_at``；若最近一次
        心跳时间早于 ``_HEARTBEAT_TIMEOUT_SECONDS``，则视为对端已断开。
        未配对时恒返回 ``False``。

        Returns:
            True 表示对端存活，False 表示未连接或已超时断开。
        """
        with self._lock:
            if not self._paired:
                return False
            return (time.time() - self._last_seen_at) <= _HEARTBEAT_TIMEOUT_SECONDS

    def create_pairing(self) -> PairingCode:
        """生成一次性配对令牌与二维码 URL。

        Returns:
            含 URL、token 与过期时间的 :class:`PairingCode`。
        """
        token = secrets.token_urlsafe(16)
        expires_at = time.time() + _TOKEN_TTL_SECONDS
        with self._lock:
            self._paired = False
            self._peer_info = None
            self._last_seen_at = 0.0
            self._token = token
            self._token_expires_at = expires_at
        url = f"http://{_get_lan_ip()}:{self.port}/pair?token={token}"
        logger.info("已生成配对二维码，token 有效期 %s 秒", _TOKEN_TTL_SECONDS)
        return PairingCode(url=url, token=token, expires_at=expires_at)

    # ------------------------------------------------------------------
    # 内部实现
    # ------------------------------------------------------------------
    def _bind_server(
        self, host: str, port: int, handler: type[BaseHTTPRequestHandler]
    ) -> ThreadingHTTPServer:
        """绑定端口，被占用时自动递增重试。

        从期望端口开始逐个尝试，最多重试 100 个端口，避免因端口冲突导致
        配对功能不可用；全部失败则抛出 OSError 交由上层处理。

        Args:
            host: 监听地址。
            port: 起始端口。
            handler: HTTP 请求处理器类型。

        Returns:
            已绑定端口并 ready 的 HTTP 服务实例。

        Raises:
            OSError: 当连续 100 个端口均不可绑定时。
        """
        last_error: OSError | None = None
        for offset in range(100):
            candidate = port + offset
            try:
                server = ThreadingHTTPServer((host, candidate), handler)
                self.port = candidate
                return server
            except OSError as exc:  # 端口占用等
                last_error = exc
                continue
        raise OSError(f"无法绑定配对服务端口（起始 {port}）: {last_error}")

    def _build_handler(self) -> type[BaseHTTPRequestHandler]:
        """构造绑定到当前传输实例的请求处理器类型。

        Returns:
            持有 ``transport`` 引用、可访问配对状态的处理器类。
        """
        transport = self

        class _PairingHandler(BaseHTTPRequestHandler):
            """处理配对握手请求的最小 HTTP 处理器。"""

            def _send_json(self, status: int, payload: dict[str, Any]) -> None:
                """统一写出 JSON 响应。"""
                body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self) -> None:  # noqa: N802 - HTTP 命名规范
                parsed = urlparse(self.path)
                if parsed.path == "/device-info":
                    self._send_json(200, transport.get_device_info().to_dict())
                else:
                    self._send_json(404, {"error": "not found"})

            def do_POST(self) -> None:  # noqa: N802 - HTTP 命名规范
                """分发 POST 请求：/pair 握手、/heartbeat 心跳。"""
                parsed = urlparse(self.path)
                if parsed.path == "/pair":
                    query = parse_qs(parsed.query)
                    token = (query.get("token") or [""])[0]
                    peer_info = self._read_peer_info()
                    self._handle_pair(token, peer_info)
                elif parsed.path == "/heartbeat":
                    self._handle_heartbeat()
                else:
                    self._send_json(404, {"error": "not found"})

            def _read_peer_info(self) -> DeviceInfo:
                """解析请求体中的对端设备信息，缺失/非法字段回退默认值。"""
                try:
                    length = int(self.headers.get("Content-Length", 0) or 0)
                    raw = self.rfile.read(length) if length > 0 else b""
                    data: dict[str, Any] = json.loads(raw.decode("utf-8")) if raw else {}
                except (ValueError, TypeError, UnicodeDecodeError):
                    data = {}
                return DeviceInfo(
                    endpoint_type=str(data.get("endpoint_type", "phone")),
                    name=str(data.get("name", "unknown")),
                    version=str(data.get("version", "")),
                    protocol_version=int(data.get("protocol_version", 0)),
                    peer_id=str(data.get("peer_id", "")),
                )

            def _handle_pair(self, token: str, peer_info: DeviceInfo) -> None:
                """校验 token 并完成握手，成功后锁定单会话并记录对端信息。"""
                with transport._lock:
                    valid = (
                        token
                        and token == transport._token
                        and time.time() <= transport._token_expires_at
                        and not transport._paired
                    )
                    if valid:
                        transport._paired = True
                        transport._token = None
                        transport._peer_info = peer_info
                        transport._last_seen_at = time.time()
                if not valid:
                    self._send_json(401, {"error": "invalid or expired token"})
                    return
                logger.info("二维码配对握手成功，对端: %s %s", peer_info.endpoint_type, peer_info.name)
                self._send_json(200, transport.get_device_info().to_dict())

            def _handle_heartbeat(self) -> None:
                """处理手机端心跳：校验 peer_id 后刷新最近心跳时间。"""
                try:
                    length = int(self.headers.get("Content-Length", 0) or 0)
                    raw = self.rfile.read(length) if length > 0 else b""
                    data: dict[str, Any] = json.loads(raw.decode("utf-8")) if raw else {}
                    peer_id = str(data.get("peer_id", ""))
                except (ValueError, TypeError, UnicodeDecodeError):
                    self._send_json(400, {"error": "invalid request body"})
                    return

                with transport._lock:
                    if not transport._paired or transport._peer_info is None:
                        self._send_json(401, {"error": "not paired"})
                        return
                    if peer_id != transport._peer_info.peer_id:
                        self._send_json(403, {"error": "peer id mismatch"})
                        return
                    transport._last_seen_at = time.time()
                self._send_json(200, {"ok": True})

            def log_message(self, format: str, *args: Any) -> None:
                """静默默认访问日志，统一走项目 logger。"""
                logger.debug("配对服务: %s", format % args if args else format)

        return _PairingHandler