/// 连接状态服务 —— 管理手机端与 PC 的连接状态并通知 UI 刷新。
///
/// 单例 [ChangeNotifier]：扫码握手成功后写入对端 [DeviceInfo] 并启动心跳
/// 定时器，主页连接卡片通过监听本服务实时更新连接状态与设备信息；心跳
/// 持续失败（PC 端掉线）时自动复位为未连接状态。
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/device_info.dart';
import 'debug_log_service.dart';
import 'qr_pairing_service.dart';

/// 心跳发送间隔（秒）：配合 PC 端 9 秒超时阈值，允许连续丢失约 3 次仍不断连。
const int _heartbeatIntervalSeconds = 3;

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._();
  static ConnectionService get instance => _instance;
  ConnectionService._();

  DeviceInfo? _peer;
  QrPairingService? _pairing;
  Timer? _heartbeatTimer;

  /// 已连接的对端（PC）设备信息，null 表示未连接。
  DeviceInfo? get peer => _peer;

  /// 是否已建立连接会话。
  bool get isConnected => _peer != null;

  /// 记录握手成功后的对端信息与传输实例，并启动心跳保活。
  ///
  /// [pairing] 完成握手、后续用于发送心跳的传输实例；其会话状态由本服务
  /// 持有，即使扫码页随后销毁，心跳仍可持续维持连接。
  void onConnected(DeviceInfo peer, QrPairingService pairing) {
    _peer = peer;
    _pairing = pairing;
    _startHeartbeat();
    notifyListeners();
  }

  /// 断开连接：停止心跳、释放会话并清空对端信息，通知监听者。
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
    _peer = null;
    notifyListeners();
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