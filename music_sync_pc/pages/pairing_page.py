"""局域网连接卡片与二维码弹窗 —— 扫描页内嵌的二维码配对连接组件。

提供 ``PairingCard``：在扫描页下方以卡片形式展示连接状态，点击「二维码连接」
启动配对服务并弹出 ``PairingQrDialog`` 展示二维码；握手成功后弹窗自动关闭，
卡片展示对端设备信息，并提供「断开连接」按钮释放服务端口。

卡片同时管理数据面（gRPC 数据传输服务）的生命周期：与配对会话同启同停，
并在已连接时轮询展示「当前传输文件 + 进度」。
"""

from __future__ import annotations

import logging
import tkinter as tk
from typing import Any, Callable

import customtkinter as ctk

from core.config import ConfigManager
from services.grpc_transport import GrpcSyncServer, TransferSnapshot
from services.qr_pairing import QrPairingTransport, render_qr_image
from services.sync_transport import PairingCode
from utils.file_utils import format_size

logger = logging.getLogger("musicsync")

_STATUS_IDLE = "未连接"
_STATUS_WAITING = "等待手机扫码..."
_STATUS_PAIRED = "已连接"
_STATUS_ERROR = "连接失败"
_STATUS_LOST = "连接已断开"
_STATUS_TRANSFER_IDLE = "暂无传输任务"

# 健康轮询间隔（毫秒）：配对成功后定时检查对端心跳是否超时
_POLL_INTERVAL_MS = 3000

# 传输进度轮询间隔（毫秒）：传输过程较短，取更小间隔以获得顺滑的进度反馈
_PROGRESS_POLL_INTERVAL_MS = 800


class PairingCard(ctk.CTkFrame):
    """扫描页内的局域网连接状态卡片。

    内部持有 :class:`QrPairingTransport` 实例，按钮驱动其 start/stop；点击
    「二维码连接」弹出 :class:`PairingQrDialog` 展示二维码，握手成功后由弹窗
    回调本卡片更新连接状态并展示对端设备信息。

    Attributes:
        config: 应用配置管理器。
        _transport: 二维码配对传输实例（None 表示未创建/已释放）。
        _grpc_server: gRPC 数据传输服务实例（None 表示未创建/已释放）。
        _dialog: 当前打开的二维码弹窗引用（None 表示未弹出）。
    """

    def __init__(self, master: Any, config: ConfigManager, **kwargs: Any) -> None:
        super().__init__(master, **kwargs)
        self.config = config
        self._transport: QrPairingTransport | None = None
        self._grpc_server: GrpcSyncServer | None = None
        self._dialog: PairingQrDialog | None = None
        self._health_after_id: str | None = None
        self._progress_after_id: str | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        """构建卡片：标题、状态行、传输进度行、连接/断开按钮。"""
        self.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(
            self,
            text="局域网连接",
            font=ctk.CTkFont(size=14, weight="bold"),
        ).grid(row=0, column=0, padx=15, pady=(12, 4), sticky="w")

        self._status_label = ctk.CTkLabel(
            self,
            text=_STATUS_IDLE,
            font=ctk.CTkFont(size=13),
            anchor="w",
        )
        self._status_label.grid(row=1, column=0, padx=15, pady=(0, 4), sticky="w")

        # 传输进度行：展示数据面当前正在读写的文件与进度，无任务时展示占位文案
        self._transfer_label = ctk.CTkLabel(
            self,
            text=_STATUS_TRANSFER_IDLE,
            font=ctk.CTkFont(size=12),
            anchor="w",
            justify="left",
        )
        self._transfer_label.grid(row=2, column=0, padx=15, pady=(0, 4), sticky="w")

        btn_frame = ctk.CTkFrame(self, fg_color="transparent")
        btn_frame.grid(row=3, column=0, padx=15, pady=(0, 12), sticky="ew")
        btn_frame.grid_columnconfigure(0, weight=1)
        btn_frame.grid_columnconfigure(1, weight=1)

        self._connect_btn = ctk.CTkButton(
            btn_frame, text="二维码连接", height=32, command=self._on_connect_clicked,
        )
        self._connect_btn.grid(row=0, column=0, padx=(0, 5), sticky="ew")

        self._disconnect_btn = ctk.CTkButton(
            btn_frame, text="断开连接", height=32, command=self._on_disconnect_clicked,
            state="disabled", fg_color="#8b2f2f", hover_color="#a33c3c",
        )
        self._disconnect_btn.grid(row=0, column=1, padx=(5, 0), sticky="ew")

    # ------------------------------------------------------------------
    # 事件回调
    # ------------------------------------------------------------------
    def _on_connect_clicked(self) -> None:
        """启动配对服务与数据面服务，并弹出二维码弹窗等待手机扫码。"""
        try:
            transport = QrPairingTransport()
            transport.start("0.0.0.0", self.config.pairing_port)
            self._transport = transport
            # 数据面与配对会话同生命周期启动；失败不阻断配对（降级为不可传输）
            self._start_grpc_server(transport)
            pairing = transport.create_pairing()

            self._status_label.configure(text=_STATUS_WAITING)
            self._connect_btn.configure(state="disabled")
            self._disconnect_btn.configure(state="normal")

            self._dialog = PairingQrDialog(
                parent=self.winfo_toplevel(),
                transport=transport,
                pairing=pairing,
                on_success=self._on_paired,
                on_cancel=self._on_dialog_cancelled,
            )
            logger.info("配对二维码弹窗已打开，等待手机扫码")
        except OSError as exc:
            logger.exception("配对服务启动失败")
            self._status_label.configure(text=f"{_STATUS_ERROR}: {exc}")
            self._stop_transport()
        except Exception as exc:  # qrcode/pillow 缺失等渲染异常
            logger.exception("二维码生成失败")
            self._status_label.configure(text=f"{_STATUS_ERROR}: {exc}")
            self._stop_transport()

    def _start_grpc_server(self, transport: QrPairingTransport) -> None:
        """启动 gRPC 数据传输服务并把实际端口登记到配对传输实例。

        端口登记后随握手响应回传手机端，供其建立数据面通道。启动失败时仅
        记录告警并保持 grpc_port=0，不影响控制面的配对与心跳。

        Args:
            transport: 已启动的配对传输实例，用于提供对端 peer_id 供鉴权。
        """
        server = GrpcSyncServer(self.config, transport.get_peer_id)
        try:
            port = server.start("0.0.0.0", self.config.grpc_port)
            self._grpc_server = server
            transport.set_grpc_port(port)
        except OSError:
            logger.exception("gRPC 数据传输服务启动失败，本次会话仅支持配对不含传输")
            server.stop()
            transport.set_grpc_port(0)

    def _on_paired(self) -> None:
        """握手成功的回调：更新状态行展示对端设备信息并启动轮询。"""
        self._dialog = None
        peer = self._transport.get_peer_info() if self._transport is not None else None
        if peer is not None:
            self._status_label.configure(
                text=f"{_STATUS_PAIRED}：{peer.name}（{peer.endpoint_type}）v{peer.version}"
            )
        else:
            self._status_label.configure(text=_STATUS_PAIRED)
        self._connect_btn.configure(state="disabled")
        self._disconnect_btn.configure(state="normal")
        self._start_health_poll()
        self._start_progress_poll()
        logger.info("配对成功，卡片已展示对端信息")

    def _on_dialog_cancelled(self) -> None:
        """用户手动关闭弹窗的回调：复位卡片状态并释放服务。"""
        self._dialog = None
        self._stop_health_poll()
        self._stop_progress_poll()
        self._stop_transport()
        self._status_label.configure(text=_STATUS_IDLE)
        self._transfer_label.configure(text=_STATUS_TRANSFER_IDLE)
        self._connect_btn.configure(state="normal")
        self._disconnect_btn.configure(state="disabled")

    def _on_disconnect_clicked(self) -> None:
        """停止配对服务并复位卡片状态（若弹窗仍打开则一并关闭）。"""
        self._close_dialog()
        self._stop_health_poll()
        self._stop_progress_poll()
        self._stop_transport()
        self._status_label.configure(text=_STATUS_IDLE)
        self._transfer_label.configure(text=_STATUS_TRANSFER_IDLE)
        self._connect_btn.configure(state="normal")
        self._disconnect_btn.configure(state="disabled")

    def _stop_transport(self) -> None:
        """安全停止并释放配对传输与 gRPC 数据面实例。"""
        transport = self._transport
        if transport is not None:
            try:
                transport.stop()
            except Exception:
                logger.exception("配对服务停止异常")
            self._transport = None
        server = self._grpc_server
        if server is not None:
            try:
                server.stop()
            except Exception:
                logger.exception("gRPC 数据传输服务停止异常")
            self._grpc_server = None

    def _close_dialog(self) -> None:
        """关闭尚未销毁的二维码弹窗（不触发取消回调）。"""
        dialog = self._dialog
        self._dialog = None
        if dialog is not None:
            dialog.close()

    # ------------------------------------------------------------------
    # 健康轮询：配对成功后定时检测对端心跳，超时自动复位连接状态
    # ------------------------------------------------------------------
    def _start_health_poll(self) -> None:
        """启动（或重置）一次健康检查的延时调度。"""
        self._stop_health_poll()
        self._health_after_id = self.after(_POLL_INTERVAL_MS, self._poll_health)

    def _stop_health_poll(self) -> None:
        """取消尚未触发的健康检查调度。"""
        if self._health_after_id is not None:
            self.after_cancel(self._health_after_id)
            self._health_after_id = None

    def _poll_health(self) -> None:
        """检查对端心跳：未连接/存活则继续轮询，超时则复位为断开状态。"""
        self._health_after_id = None
        transport = self._transport
        if transport is None or not transport.is_paired:
            return
        if not transport.is_peer_alive():
            logger.info("检测到对端心跳超时，自动判定连接已断开")
            self._on_connection_lost()
            return
        self._start_health_poll()

    def _on_connection_lost(self) -> None:
        """对端掉线后的复位：停止服务、更新状态行并恢复按钮。"""
        self._stop_progress_poll()
        self._stop_transport()
        self._status_label.configure(text=_STATUS_LOST)
        self._transfer_label.configure(text=_STATUS_TRANSFER_IDLE)
        self._connect_btn.configure(state="normal")
        self._disconnect_btn.configure(state="disabled")

    # ------------------------------------------------------------------
    # 传输进度轮询：读取 gRPC 服务记录的进度快照，展示当前传输文件与进度
    # ------------------------------------------------------------------
    def _start_progress_poll(self) -> None:
        """启动（或重置）一次传输进度刷新的延时调度。"""
        self._stop_progress_poll()
        self._progress_after_id = self.after(
            _PROGRESS_POLL_INTERVAL_MS, self._poll_transfer_progress
        )

    def _stop_progress_poll(self) -> None:
        """取消尚未触发的传输进度调度。"""
        if self._progress_after_id is not None:
            self.after_cancel(self._progress_after_id)
            self._progress_after_id = None

    def _poll_transfer_progress(self) -> None:
        """刷新传输进度文案；传输结束后回到占位文案，并继续轮询。"""
        self._progress_after_id = None
        server = self._grpc_server
        if server is None:
            return
        self._transfer_label.configure(text=self._format_transfer_text(server.progress.snapshot()))
        self._start_progress_poll()

    @staticmethod
    def _format_transfer_text(snapshot: TransferSnapshot) -> str:
        """把进度快照格式化为卡片上的一行文案。

        Args:
            snapshot: gRPC 服务当前记录的进度快照。

        Returns:
            形如「上传中 40% · a.mp3（4.0 MB / 10.0 MB）」的可读文案；
            无传输时返回占位文案。
        """
        if not snapshot.active:
            return _STATUS_TRANSFER_IDLE
        action = "上传中" if snapshot.direction == "upload" else "下发中"
        name = snapshot.relative_path.rsplit("/", 1)[-1]
        if snapshot.total_bytes > 0:
            percent = int(snapshot.transferred_bytes * 100 / snapshot.total_bytes)
            size_text = f"{format_size(snapshot.transferred_bytes)} / {format_size(snapshot.total_bytes)}"
            return f"{action} {percent}% · {name}（{size_text}）"
        return f"{action} · {name}（{format_size(snapshot.transferred_bytes)}）"

    # ------------------------------------------------------------------
    # 公开接口
    # ------------------------------------------------------------------
    def on_close(self) -> None:
        """卡片销毁前停止服务、健康轮询与进度轮询，释放端口与线程。"""
        self._close_dialog()
        self._stop_health_poll()
        self._stop_progress_poll()
        self._stop_transport()


class PairingQrDialog(ctk.CTkToplevel):
    """二维码配对弹窗 —— 展示二维码并后台轮询握手结果。

    弹窗内部通过 ``after`` 固定间隔轮询 ``transport.is_paired``，一旦握手成功
    立即回调 ``on_success`` 并销毁自身；用户主动点击取消/关闭则回调
    ``on_cancel``。

    Attributes:
        transport: 共享的配对传输实例（由卡片持有）。
        pairing: 本次配对信息（含二维码 URL）。
        _on_success: 握手成功回调。
        _on_cancel: 用户取消回调。
        _closed: 是否已结束（防重复回调）。
    """

    def __init__(
        self,
        parent: Any,
        transport: QrPairingTransport,
        pairing: PairingCode,
        on_success: Callable[[], None],
        on_cancel: Callable[[], None],
        **kwargs: Any,
    ) -> None:
        super().__init__(parent, **kwargs)
        self.transport = transport
        self.pairing = pairing
        self._on_success = on_success
        self._on_cancel = on_cancel
        self._closed = False
        self._qr_image_ref: Any = None

        self.title("扫码连接")
        self.resizable(False, False)
        self._build_ui()
        self._center_over_parent(parent)

        # 模态：挂到父窗口之上并截获输入，稍后窗口映射完成再 grab
        self.transient(parent)
        self.protocol("WM_DELETE_WINDOW", self._on_user_cancel)
        self.after(100, self._apply_modal)
        self._poll_pairing_result()

    def _build_ui(self) -> None:
        """构建弹窗：二维码图片、提示文案、取消按钮。"""
        self.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(
            self,
            text="扫描二维码连接 PC",
            font=ctk.CTkFont(size=15, weight="bold"),
        ).grid(row=0, column=0, padx=20, pady=(20, 8))

        # 二维码展示区：浅色背景便于扫描
        pil_img = render_qr_image(self.pairing.url)
        self._qr_image_ref = ctk.CTkImage(
            light_image=pil_img, dark_image=pil_img, size=(240, 240),
        )
        self._qr_label = ctk.CTkLabel(
            self, text="", image=self._qr_image_ref, width=240, height=240,
        )
        self._qr_label.grid(row=1, column=0, padx=20, pady=8)

        ctk.CTkLabel(
            self,
            text="请使用手机 MusicSync 扫描此二维码",
            font=ctk.CTkFont(size=12),
        ).grid(row=2, column=0, padx=20, pady=(8, 4))

        ctk.CTkButton(
            self, text="取消", width=120, command=self._on_user_cancel,
        ).grid(row=3, column=0, padx=20, pady=(4, 20))

    def _center_over_parent(self, parent: Any) -> None:
        """将弹窗居中于父窗口（父窗口坐标可能尚未稳定，采用尽力而为定位）。"""
        self.update_idletasks()
        parent.update_idletasks()
        pw, ph = parent.winfo_width(), parent.winfo_height()
        px, py = parent.winfo_rootx(), parent.winfo_rooty()
        w, h = self.winfo_width(), self.winfo_height()
        x = px + max((pw - w) // 2, 0)
        y = py + max((ph - h) // 2, 0)
        self.geometry(f"+{x}+{y}")

    def _apply_modal(self) -> None:
        """窗口映射完成后截获输入，实现模态行为。"""
        if self._closed:
            return
        try:
            self.grab_set()
        except tk.TclError:
            pass

    def _on_user_cancel(self) -> None:
        """用户点击取消或关闭窗口：回调取消并销毁。"""
        self._finish(self._on_cancel)

    def _finish(self, callback: Callable[[], None]) -> None:
        """统一收尾：防重复回调、执行回调并销毁弹窗。"""
        if self._closed:
            return
        self._closed = True
        try:
            callback()
        finally:
            self.destroy()

    def close(self) -> None:
        """外部主动关闭弹窗（不触发任何回调），仅做收尾销毁。"""
        if self._closed:
            return
        self._closed = True
        self.destroy()

    def _poll_pairing_result(self) -> None:
        """轮询握手结果：成功则回调收尾，否则继续定时轮询。"""
        if self._closed:
            return
        try:
            alive = self.winfo_exists()
        except tk.TclError:
            return
        if not alive:
            return
        if self.transport.is_paired:
            self._finish(self._on_success)
            return
        self.after(500, self._poll_pairing_result)