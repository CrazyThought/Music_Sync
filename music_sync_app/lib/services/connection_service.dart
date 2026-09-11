/// 连接状态服务 —— 管理手机端与 PC 的连接状态并通知 UI 刷新。
///
/// 单例 [ChangeNotifier]：扫码握手成功后写入对端 [DeviceInfo] 并启动心跳
/// 定时器，主页连接卡片通过监听本服务实时更新连接状态与设备信息；心跳
/// 持续失败（PC 端掉线）时自动复位为未连接状态。
///
/// 同时持有数据面客户端 [GrpcSyncClient] 的生命周期：握手成功后按 PC 回传的
/// gRPC 端口建连，断开时一并关闭，保证连接状态与数据通道同生共死。
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/device_info.dart';
import 'debug_log_service.dart';
import 'grpc_sync_client.dart';
import 'qr_pairing_service.dart';

/// 心跳发送间隔（秒）：配合 PC 端 9 秒超时阈值，允许连续丢失约 3 次仍不断连。
const int _heartbeatIntervalSeconds = 3;

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._();
  static ConnectionService get instance => _instance;
  ConnectionService._();

  DeviceInfo? _peer;
  QrPairingService? _pairing;
  GrpcSyncClient? _syncClient;
  Timer? _heartbeatTimer;

  /// 已连接的对端（PC）设备信息，null 表示未连接。
  DeviceInfo? get peer => _peer;

  /// 是否已建立连接会话。
  bool get isConnected => _peer != null;

  /// 数据面客户端；PC 端未开启 gRPC 服务或未连接时为 null。
  GrpcSyncClient? get syncClient => _syncClient;

  /// 数据面是否可用（已连接且 PC 端提供 gRPC 服务）。
  bool get isDataChannelReady => _syncClient != null;

  /// 记录握手成功后的对端信息与传输实例，并启动心跳保活。
  ///
  /// [pairing] 完成握手、后续用于发送心跳的传输实例；其会话状态由本服务
  /// 持有，即使扫码页随后销毁，心跳仍可持续维持连接。
  void onConnected(DeviceInfo peer, QrPairingService pairing) {
    _peer = peer;
    _pairing = pairing;
    _openSyncClient(pairing);
    _startHeartbeat();
    notifyListeners();
  }

  /// 断开连接：停止心跳、释放会话与数据通道并清空对端信息，通知监听者。
  ///
  /// 既供用户主动断开调用，也供心跳失败（检测到 PC 端掉线）时自动复位。
  void disconnect() {
    _stopHeartbeat();
    final pairing = _pairing;
    _pairing = null;
    if (pairing != null) {
      // 断开为纯状态清理，无需等待结果
      unawaited(pairing.disconnect());
    }
    _closeSyncClient();
    _peer = null;
    notifyListeners();
  }

  /// 按握手结果建立 gRPC 数据通道。
  ///
  /// PC 端未启用数据面（grpc_port 为 0）或缺少必要信息时不建立，此时
  /// [syncClient] 为 null，同步页会给出明确提示而非静默失败。
  void _openSyncClient(QrPairingService pairing) {
    _closeSyncClient();
    final host = pairing.baseUri?.host ?? '';
    final client = GrpcSyncClient(
      host: host,
      port: pairing.grpcPort,
      peerId: pairing.selfPeerId ?? '',
    );
    if (!client.isAvailable) {
      DebugLogService.instance.error(
        'PC 端未提供数据通道（grpc_port=${pairing.grpcPort}），本次会话无法传输文件',
      );
      return;
    }
    client.open();
    _syncClient = client;
  }

  /// 关闭数据通道并释放资源。
  void _closeSyncClient() {
    final client = _syncClient;
    _syncClient = null;
    if (client != null) {
      unawaited(client.close());
    }
  }

  /// 启动心跳定时器（重复启动前先取消旧定时器）。
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatIntervalSeconds),
      (_) => _sendHeartbeat(),
    );
  }

  /// 停止心跳定时器并释放引用。
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 发送一次心跳，失败表示 PC 端不可达，自动断开连接。
  Future<void> _sendHeartbeat() async {
    final pairing = _pairing;
    if (pairing == null) return;
    try {
      await pairing.heartbeat();
    } catch (e) {
      // 心跳失败（网络不可达 / 超时 / 校验不通过）视为 PC 端已断开
      DebugLogService.instance.error('心跳失败，判定 PC 已断开: $e');
      disconnect();
    }
  }
}