"""gRPC 数据传输服务 —— 承载特征签名拉取与音频文件双向传输。

架构定位（控制面 / 数据面分离）：

- **控制面**：发现、配对、握手、心跳由 ``services/qr_pairing.py`` 的 HTTP 通道承载；
- **数据面**：签名拉取与文件双向传输由本模块的 gRPC 服务承载。

两层通过握手产生的 ``peer_id`` 桥接：手机端在 gRPC metadata 中回传本机
``peer-id``，服务端校验其是否等于当前配对会话记录的对端 id，未通过则返回
``UNAUTHENTICATED``，避免局域网内其它设备蹭取音乐文件。

对外提供的能力：

- ``GetSignature``：下发 PC 端最新特征签名；
- ``DownloadFile``：从指定偏移流式下发文件（支持断点续传）；
- ``UploadFile``：接收手机端上传的文件分块（支持断点续传）；
- ``GetUploadStatus``：查询服务端已接收字节数，供上传续传定位偏移。

安全约束：所有相对路径统一经 :func:`_resolve_within_root` 规范化，拒绝任何
逃逸出音乐根目录的读写（防路径遍历）。
"""

from __future__ import annotations

import json
import logging
import os
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Callable, Iterator

import grpc

from core.config import ConfigManager
from generated import musicsync_pb2, musicsync_pb2_grpc
from services.hash_utils import compute_chunked_hash, compute_xxhash64
from services.signature import load_signature
from utils.constants import (
    DEFAULT_GRPC_PORT,
    GRPC_MAX_WORKERS,
    GRPC_TRANSFER_CHUNK_SIZE,
    GRPC_UPLOAD_PART_SUFFIX,
    LARGE_FILE_THRESHOLD_BYTES,
    SIGNATURE_FILE_NAME,
)

logger = logging.getLogger("musicsync")

# gRPC metadata 中携带对端标识的键名（gRPC 规范要求小写）
_PEER_ID_METADATA_KEY = "peer-id"


# ======================================================================
# 传输进度快照
# ======================================================================
@dataclass(frozen=True)
class TransferSnapshot:
    """一次文件传输的进度快照，供 PC 端 UI 轮询展示。

    Attributes:
        active: 当前是否有传输在进行。
        direction: 传输方向，``"download"``（下发手机）或 ``"upload"``（手机上传）。
        relative_path: 正在传输的文件相对路径。
        transferred_bytes: 已传输字节数。
        total_bytes: 文件总字节数；未知时为 0。
    """

    active: bool = False
    direction: str = ""
    relative_path: str = ""
    transferred_bytes: int = 0
    total_bytes: int = 0


class TransferProgress:
    """线程安全的传输进度记录器。

    gRPC 服务在工作线程中读写进度，PC 端 UI 在主线程轮询读取，因此所有
    读写都通过内部锁保护，避免竞态。
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._snapshot = TransferSnapshot()

    def begin(self, direction: str, relative_path: str, total_bytes: int) -> None:
        """开始一次传输，重置进度快照。

        Args:
            direction: 传输方向（``"download"`` / ``"upload"``）。
            relative_path: 文件相对路径。
            total_bytes: 文件总字节数；未知时传 0。
        """
        with self._lock:
            self._snapshot = TransferSnapshot(
                active=True,
                direction=direction,
                relative_path=relative_path,
                transferred_bytes=0,
                total_bytes=total_bytes,
            )

    def set_transferred(self, value: int) -> None:
        """直接设置已传输字节数（上传流按分块偏移推进时使用）。"""
        with self._lock:
            self._snapshot = replace(self._snapshot, transferred_bytes=value)

    def advance(self, delta: int) -> None:
        """在已传输字节数上累加（下载流逐块下发时使用）。"""
        with self._lock:
            self._snapshot = replace(
                self._snapshot,
                transferred_bytes=self._snapshot.transferred_bytes + delta,
            )

    def finish(self) -> None:
        """结束当前传输，标记为非活跃。"""
        with self._lock:
            self._snapshot = replace(self._snapshot, active=False)

    def reset(self) -> None:
        """清空进度快照（服务停止时调用）。"""
        with self._lock:
            self._snapshot = TransferSnapshot()

    def snapshot(self) -> TransferSnapshot:
        """返回当前进度快照的副本。"""
        with self._lock:
            return self._snapshot


# ======================================================================
# 路径安全
# ======================================================================
def _resolve_within_root(root: Path, relative_path: str) -> Path:
    """把相对路径解析到音乐根目录下的绝对路径，并阻断路径遍历。

    先统一分隔符为 ``/`` 并去掉前导斜杠，再拼接根目录后取真实路径
    （``resolve`` 会展开 ``..`` 与符号链接），最后校验结果仍位于根目录内。

    Args:
        root: 音乐库根目录。
        relative_path: 客户端提供的相对路径（可能含 ``/`` 或 ``\\``）。

    Returns:
        规范化后的绝对路径。

    Raises:
        ValueError: 路径为空，或规范化后逃逸出根目录时。
    """
    if not relative_path or not relative_path.strip():
        raise ValueError("relative_path 不能为空")

    normalized = relative_path.replace("\\", "/").lstrip("/")
    root_resolved = root.resolve()
    candidate = (root_resolved / normalized).resolve()
    # is_relative_to 保证路径未被 .. / 绝对路径 / 符号链接带出根目录
    if not candidate.is_relative_to(root_resolved):
        raise ValueError(f"路径越权，超出音乐根目录: {relative_path}")
    return candidate


# ======================================================================
# 签名 JSON -> proto 转换
# ======================================================================
def _signature_payload(data: dict[str, Any]) -> musicsync_pb2.SignatureResponse:
    """把 PC 端签名字典封装为 gRPC 响应消息。

    签名体整体以 SIGNATURE_SPEC v2.0 的 JSON 字节承载，不在 proto 中重复定义
    文件条目 schema，保证 `docs/SIGNATURE_SPEC.md` 为唯一事实来源，两端直接复用
    既有的序列化与版本校验实现。

    Args:
        data: :func:`services.signature.load_signature` 返回的签名字典。

    Returns:
        含 JSON 字节的 gRPC ``SignatureResponse`` 消息。
    """
    payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
    return musicsync_pb2.SignatureResponse(json=payload)


# ======================================================================
# 鉴权拦截器
# ======================================================================
class _PeerAuthInterceptor(grpc.ServerInterceptor):
    """基于 ``peer-id`` metadata 的会话鉴权拦截器。

    在请求进入业务处理前校验 metadata 中的 ``peer-id`` 是否等于当前配对
    会话记录的对端标识；不通过时返回与原方法同形态的「拒绝处理器」，
    直接以 ``UNAUTHENTICATED`` 终止，避免任何文件读写发生。

    Attributes:
        _peer_id_provider: 返回当前已配对对端 id 的回调；未配对时返回 None。
    """

    def __init__(self, peer_id_provider: Callable[[], str | None]) -> None:
        self._peer_id_provider = peer_id_provider

    def intercept_service(  # noqa: D102 - 覆盖基类方法，说明见类文档
        self,
        continuation: Callable[[Any], Any],
        handler_call_details: Any,
    ) -> Any:
        handler = continuation(handler_call_details)
        if handler is None or self._is_authorized(handler_call_details):
            return handler
        logger.warning("gRPC 请求鉴权失败: %s", handler_call_details.method)
        return self._build_deny_handler(handler)

    def _is_authorized(self, handler_call_details: Any) -> bool:
        """校验请求 metadata 中的 peer-id 是否为当前配对会话的对端。"""
        expected = self._peer_id_provider()
        if not expected:
            return False
        metadata = dict(handler_call_details.invocation_metadata or ())
        return metadata.get(_PEER_ID_METADATA_KEY, "") == expected

    @staticmethod
    def _build_deny_handler(handler: Any) -> grpc.RpcMethodHandler:
        """构造与方法形态（一元/流式）一致的拒绝处理器。

        gRPC 要求处理器回调形态与 RPC 类型严格匹配，因此按原方法的
        request_streaming / response_streaming 组合，用官方工厂函数构造，
        否则协议层会直接报错而非返回预期状态码。
        """

        def _abort_unary(request: Any, context: grpc.ServicerContext) -> None:
            context.abort(grpc.StatusCode.UNAUTHENTICATED, "peer-id 校验失败或会话未建立")

        def _abort_stream(request: Any, context: grpc.ServicerContext) -> Iterator[Any]:
            # 含 yield 使其成为生成器，匹配流式响应契约；abort 会直接抛出终止
            context.abort(grpc.StatusCode.UNAUTHENTICATED, "peer-id 校验失败或会话未建立")
            yield  # pragma: no cover - 仅为满足生成器语法

        if handler.request_streaming:
            if handler.response_streaming:
                return grpc.stream_stream_rpc_method_handler(_abort_stream)
            return grpc.stream_unary_rpc_method_handler(_abort_unary)
        if handler.response_streaming:
            return grpc.unary_stream_rpc_method_handler(_abort_stream)
        return grpc.unary_unary_rpc_method_handler(_abort_unary)


# ======================================================================
# 业务实现
# ======================================================================
class MusicSyncServicer(musicsync_pb2_grpc.MusicSyncServicer):
    """MusicSync gRPC 服务实现。

    承接签名拉取与文件双向传输；文件读写的根目录优先取签名中的
    ``scan_root``（与 PC 端扫描时一致），缺失时回退配置中的音乐目录。

    Attributes:
        _config: 应用配置管理器。
        _progress: 传输进度记录器（供 UI 轮询）。
    """

    def __init__(self, config: ConfigManager, progress: TransferProgress) -> None:
        self._config = config
        self._progress = progress

    # ------------------------------------------------------------------
    # 内部工具
    # ------------------------------------------------------------------
    def _signature_path(self) -> Path:
        """返回 PC 端签名文件路径（位于签名导出目录下）。"""
        return Path(self._config.output_folder) / SIGNATURE_FILE_NAME

    def _load_signature_dict(self) -> dict[str, Any] | None:
        """读取并校验签名文件；不存在或非法时返回 None。"""
        try:
            return load_signature(self._signature_path())
        except (OSError, ValueError, FileNotFoundError):
            return None

    def _music_root(self) -> Path | None:
        """确定文件读写根目录。

        优先使用签名中的 ``scan_root``，保证与 PC 端扫描结果指向同一目录；
        尚无签名时回退到配置中的音乐文件夹。两者都不可用时返回 None。
        """
        data = self._load_signature_dict()
        if data is not None:
            root = str(data.get("scan_root") or "").strip()
            if root:
                return Path(root)
        folder = self._config.music_folder.strip()
        return Path(folder) if folder else None

    def _require_music_root(self, context: grpc.ServicerContext) -> Path:
        """获取根目录，缺失时以 FAILED_PRECONDITION 终止请求。"""
        root = self._music_root()
        if root is None:
            context.abort(
                grpc.StatusCode.FAILED_PRECONDITION,
                "PC 端未配置音乐目录，请先在扫描页选择音乐文件夹",
            )
        return root

    # ------------------------------------------------------------------
    # RPC 实现
    # ------------------------------------------------------------------
    def GetSignature(
        self,
        request: musicsync_pb2.GetSignatureRequest,
        context: grpc.ServicerContext,
    ) -> musicsync_pb2.SignatureResponse:
        """下发 PC 端最新特征签名（JSON 字节）。"""
        data = self._load_signature_dict()
        if data is None:
            context.abort(
                grpc.StatusCode.NOT_FOUND,
                "PC 端尚未生成特征签名，请先扫描音乐并导出签名",
            )
        logger.info("gRPC 下发签名: %s 首", len(data.get("files", []) or []))
        return _signature_payload(data)

    def DownloadFile(
        self,
        request: musicsync_pb2.DownloadRequest,
        context: grpc.ServicerContext,
    ) -> Iterator[musicsync_pb2.FileChunk]:
        """从 offset 起分块下发文件，实现断点续传。"""
        root = self._require_music_root(context)
        try:
            target = _resolve_within_root(root, request.relative_path)
        except ValueError as exc:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, str(exc))

        if not target.is_file():
            context.abort(grpc.StatusCode.NOT_FOUND, f"文件不存在: {request.relative_path}")

        total = target.stat().st_size
        offset = max(0, int(request.offset))
        if offset > total:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "续传偏移超出文件大小")

        logger.info("gRPC 开始下发: %s（偏移 %s / 共 %s 字节）",
                    request.relative_path, offset, total)
        self._progress.begin("download", request.relative_path, total)
        sent = offset
        try:
            with open(target, "rb") as handle:
                if offset:
                    handle.seek(offset)
                while True:
                    chunk = handle.read(GRPC_TRANSFER_CHUNK_SIZE)
                    if not chunk:
                        break
                    yield musicsync_pb2.FileChunk(
                        relative_path=request.relative_path,
                        offset=sent,
                        data=chunk,
                        total_size=total,
                    )
                    sent += len(chunk)
                    # 以文件内绝对位置上报，续传时进度条能反映真实位置
                    self._progress.set_transferred(sent)
        finally:
            self._progress.finish()
            logger.info("gRPC 下发结束: %s（已发 %s 字节）", request.relative_path, sent - offset)

    def UploadFile(
        self,
        request_iterator: Iterator[musicsync_pb2.FileChunk],
        context: grpc.ServicerContext,
    ) -> musicsync_pb2.UploadResponse:
        """接收手机端上传的分块，按 offset 续接写入。"""
        root = self._require_music_root(context)

        relative_path = ""
        target: Path | None = None
        part_path: Path | None = None
        handle: Any = None
        received = 0
        total = 0

        try:
            for chunk in request_iterator:
                # 首个数据块携带 relative_path，用于定位写入目标
                if not relative_path:
                    relative_path = chunk.relative_path
                    if not relative_path:
                        context.abort(grpc.StatusCode.INVALID_ARGUMENT, "首个数据块缺少 relative_path")
                    try:
                        target = _resolve_within_root(root, relative_path)
                    except ValueError as exc:
                        context.abort(grpc.StatusCode.INVALID_ARGUMENT, str(exc))
                    part_path = target.with_name(target.name + GRPC_UPLOAD_PART_SUFFIX)
                    part_path.parent.mkdir(parents=True, exist_ok=True)
                    # 已存在分块文件则以读写模式打开，支持从断点继续写入
                    handle = open(part_path, "r+b" if part_path.exists() else "wb")
                    total = int(chunk.total_size)
                    logger.info("gRPC 接收上传: %s（总大小 %s 字节）", relative_path, total)
                    self._progress.begin("upload", relative_path, total)

                if handle is None or part_path is None:
                    context.abort(grpc.StatusCode.INTERNAL, "上传会话初始化失败")

                handle.seek(int(chunk.offset))
                handle.write(chunk.data)
                received = int(chunk.offset) + len(chunk.data)
                self._progress.set_transferred(received)

            if handle is None:
                context.abort(grpc.StatusCode.INVALID_ARGUMENT, "未收到任何数据块")

            # 截断多余尾部：客户端重传时可能留下比本次更长的旧分块。
            # 先 flush 让磁盘长度可见，且仅在「实际长度不小于目标长度」时截断，
            # 避免 offset 跳到文件末尾之外时 truncate 用零字节把文件撑大。
            handle.flush()
            if os.path.getsize(part_path) >= received:
                handle.truncate(received)
            handle.close()
            handle = None
        finally:
            if handle is not None:
                handle.close()

        # 完成条件：已收字节覆盖声明总大小，且实际落盘长度与声明一致。
        # 后者用于防住「客户端声明 offset 已到末尾但文件实际偏短」的异常场景。
        completed = received >= total
        content_hash = ""
        if completed and target is not None and part_path is not None:
            if os.path.getsize(part_path) != received:
                completed = False
            else:
                # 全部接收后原子落盘为正式文件，避免半成品被扫描进音乐库
                os.replace(part_path, target)
                # 哈希策略必须与扫描器一致，否则客户端无法用它回验本地文件：
                # 大文件（>= 阈值）取首尾分块，小文件全量计算。
                try:
                    size = target.stat().st_size
                    content_hash = (
                        compute_chunked_hash(target, size, self._config.chunk_hash_size)
                        if size >= LARGE_FILE_THRESHOLD_BYTES
                        else compute_xxhash64(target)
                    )
                except OSError:
                    content_hash = ""

        self._progress.finish()
        logger.info("gRPC 上传结束: %s（完成=%s，已收 %s 字节）", relative_path, completed, received)
        return musicsync_pb2.UploadResponse(
            relative_path=relative_path,
            received_bytes=received,
            completed=completed,
            content_hash=content_hash,
        )

    def GetUploadStatus(
        self,
        request: musicsync_pb2.UploadStatusRequest,
        context: grpc.ServicerContext,
    ) -> musicsync_pb2.UploadResponse:
        """查询服务端已接收字节数，供上传断点续传定位偏移。

        仅以「未完成的分块文件」衡量续传进度：正式文件是否已存在不参与判断，
        因为上传语义为「以手机端版本覆盖 PC 端」，存在旧版本也必须重传覆盖。
        """
        root = self._require_music_root(context)
        try:
            target = _resolve_within_root(root, request.relative_path)
        except ValueError as exc:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, str(exc))

        part_path = target.with_name(target.name + GRPC_UPLOAD_PART_SUFFIX)
        if part_path.is_file():
            return musicsync_pb2.UploadResponse(
                relative_path=request.relative_path,
                received_bytes=part_path.stat().st_size,
                completed=False,
            )

        return musicsync_pb2.UploadResponse(
            relative_path=request.relative_path, received_bytes=0, completed=False,
        )


# ======================================================================
# 服务生命周期管理
# ======================================================================
class GrpcSyncServer:
    """gRPC 数据传输服务的启动/停止封装。

    与 HTTP 配对服务同生命周期：配对会话建立时启动，断开或程序退出时停止
    并释放端口与线程，避免端口泄露。

    Attributes:
        progress: 传输进度记录器，供 PC 端 UI 轮询展示。
    """

    def __init__(self, config: ConfigManager, peer_id_provider: Callable[[], str | None]) -> None:
        """初始化服务封装。

        Args:
            config: 应用配置管理器。
            peer_id_provider: 返回当前已配对对端 id 的回调，供鉴权拦截器使用。
        """
        self._config = config
        self._peer_id_provider = peer_id_provider
        self._server: grpc.Server | None = None
        self._executor: ThreadPoolExecutor | None = None
        self._port: int = 0
        self.progress = TransferProgress()

    @property
    def port(self) -> int:
        """实际监听端口；未启动时为 0。"""
        return self._port

    def start(self, host: str = "0.0.0.0", port: int = DEFAULT_GRPC_PORT) -> int:
        """启动服务并返回实际监听端口，端口占用时自动递增重试。

        Args:
            host: 监听地址。
            port: 期望端口。

        Returns:
            实际绑定成功的端口。

        Raises:
            OSError: 连续 100 个候选端口均无法绑定时。
        """
        self._executor = ThreadPoolExecutor(
            max_workers=GRPC_MAX_WORKERS, thread_name_prefix="grpc-sync"
        )
        # 单块 256KB，预留一倍余量给消息头，避免大分块触发默认 4MB 上限
        max_message_bytes = GRPC_TRANSFER_CHUNK_SIZE * 2
        try:
            for offset in range(100):
                candidate = port + offset
                server = grpc.server(
                    self._executor,
                    interceptors=(_PeerAuthInterceptor(self._peer_id_provider),),
                    options=(
                        ("grpc.max_send_message_length", max_message_bytes),
                        ("grpc.max_receive_message_length", max_message_bytes),
                    ),
                )
                musicsync_pb2_grpc.add_MusicSyncServicer_to_server(
                    MusicSyncServicer(self._config, self.progress), server
                )
                bound = server.add_insecure_port(f"{host}:{candidate}")
                if bound:
                    server.start()
                    self._server = server
                    self._port = bound
                    logger.info("gRPC 数据传输服务已启动: %s:%s", host, bound)
                    return bound
                server.stop(0)
            raise OSError(f"无法绑定 gRPC 服务端口（起始 {port}）")
        except Exception:
            self._shutdown_executor()
            raise

    def stop(self) -> None:
        """停止服务并释放端口、线程与进度状态。"""
        server = self._server
        self._server = None
        self._port = 0
        if server is not None:
            # grace=0：立即终止，避免断开连接时 UI 卡顿
            server.stop(0)
        self._shutdown_executor()
        self.progress.reset()
        logger.info("gRPC 数据传输服务已停止")

    def _shutdown_executor(self) -> None:
        """关闭工作线程池（不等待在途任务）。"""
        executor = self._executor
        self._executor = None
        if executor is not None:
            executor.shutdown(wait=False)
