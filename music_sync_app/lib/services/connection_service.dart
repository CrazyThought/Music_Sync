/// 连接状态服务 —— 管理手机端与 PC 的连接状态并通知 UI 刷新。
///
/// 单例 [ChangeNotifier]：扫码握手成功后写入对端 [DeviceInfo]，主页连接
/// 卡片通过监听本服务实时更新连接状态与设备信息。
import 'package:flutter/foundation.dart';

import '../models/device_info.dart';

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._();
  static ConnectionService get instance => _instance;
  ConnectionService._();

  DeviceInfo? _peer;

  /// 已连接的对端（PC）设备信息，null 表示未连接。
  DeviceInfo? get peer => _peer;

  /// 是否已建立连接会话。
  bool get isConnected => _peer != null;

  /// 记录握手成功后的对端（PC）设备信息并通知监听者。
  void onConnected(DeviceInfo peer) {
    _peer = peer;
    notifyListeners();
  }

  /// 断开连接：清空对端信息并通知监听者。
  ///
  /// 当前握手为一次性确认、无长连接，断开仅清本地状态；服务端端口由 PC 端
  /// 在断开或重新配对时自行释放。
  void disconnect() {
    _peer = null;
    notifyListeners();
  }
}