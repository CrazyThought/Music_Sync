/// 二维码配对连接服务 —— 解析二维码内容并发起 /pair 握手。
///
/// 二维码携带配对 URL（`http://<ip>:<port>/pair?token=<rand>`），本服务
/// 通过 [connect] 以 POST 访问该 URL，请求体携带本机 [DeviceInfo]，完成
/// 握手后返回对端（PC）的 [DeviceInfo]。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/device_info.dart';
import '../utils/constants.dart';
import 'sync_transport.dart';

/// 握手请求超时时间（秒）。
const int _connectTimeoutSeconds = 5;

class QrPairingService implements SyncTransport {
  final Random _random = Random.secure();

  @override
  Future<DeviceInfo> connect(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: _connectTimeoutSeconds);

    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType.json;
      // 回传本机设备信息，供 PC 端解析并展示连接对象
      final localInfo = _buildLocalDeviceInfo();
      request.add(utf8.encode(jsonEncode(localInfo.toJson())));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      // 401 表示 token 无效/过期/已消费，视为配对失败
      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException('配对失败：二维码已失效或已被使用');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      return DeviceInfo.fromJson(json);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> disconnect() async {
    // 当前为无状态握手，无需额外释放；后续若维护持久会话则在此关闭连接
  }

  /// 构造本机设备信息，随握手请求回传给 PC 端展示。
  ///
  /// 设备名取系统主机名（异常或为空时回退 `AndroidDevice`）；peerId 为
  /// 会话级随机值，当前阶段仅用于身份展示，跨会话不要求稳定。
  DeviceInfo _buildLocalDeviceInfo() {
    var name = '';
    try {
      name = Platform.localHostname;
    } catch (_) {
      name = '';
    }
    if (name.isEmpty) name = 'AndroidDevice';

    return DeviceInfo(
      endpointType: 'phone',
      name: name,
      version: appVersion,
      protocolVersion: transportProtocolVersion,
      peerId: _generatePeerId(),
    );
  }

  /// 生成 8 字节随机数的十进制十六进制串作为会话 peerId。
  String _generatePeerId() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}