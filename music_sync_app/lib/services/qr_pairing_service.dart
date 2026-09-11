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

/// 心跳请求超时时间（秒）。
const int _heartbeatTimeoutSeconds = 3;

class QrPairingService implements SyncTransport {
  final Random _random = Random.secure();

  /// 握手成功后保存的服务基地址（scheme/host/port），供后续心跳复用。
  Uri? _baseUri;

  /// 本次会话本机的 peerId，随握手与心跳一并发送，供 PC 端校验身份。
  String? _selfPeerId;

  @override
  Future<DeviceInfo> connect(Uri uri) async {
    // 记录服务基地址：后续心跳请求直接拼 /heartbeat 路径
    _baseUri = Uri(scheme: uri.scheme, host: uri.host, port: uri.port);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: _connectTimeoutSeconds);

    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType.json;
      // 回传本机设备信息，供 PC 端解析并展示连接对象。
      // 显式设置 contentLength：dart:io 默认 contentLength=-1 会走 chunked 分块
      // 编码，而 PC 端 BaseHTTPRequestHandler 不解析 chunked 请求体，会读不到
      // body 并残留未读字节触发 RST；改为 Content-Length 让服务端正确读取。
      final localInfo = _buildLocalDeviceInfo();
      final bodyBytes = utf8.encode(jsonEncode(localInfo.toJson()));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

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

  /// 向 PC 端发送一次心跳，校验失败或网络错误时抛出异常。
  ///
  /// 供 [ConnectionService] 定时调用以维持连接；未完成握手（无基地址或
  /// 无 peerId）时抛出 [StateError]，网络异常或非 200 响应抛出其它异常。
  Future<void> heartbeat() async {
    final base = _baseUri;
    final peerId = _selfPeerId;
    if (base == null || peerId == null) {
      throw StateError('尚未建立连接，无法发送心跳');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: _heartbeatTimeoutSeconds);
    try {
      final request = await client.postUrl(base.resolve('/heartbeat'));
      request.headers.contentType = ContentType.json;
      // 显式声明 Content-Length，避免 chunked 请求体被 PC 端忽略（同 connect）
      final bodyBytes = utf8.encode(jsonEncode({'peer_id': peerId}));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException('心跳失败：服务端未接受');
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> disconnect() async {
    // 清理会话状态：释放基地址与 peerId，终止后续心跳
    _baseUri = null;
    _selfPeerId = null;
  }

  /// 构造本机设备信息，随握手请求回传给 PC 端展示。
  ///
  /// 设备名取系统主机名（异常或为空时回退 `AndroidDevice`）；peerId 为
  /// 会话级随机值，生成后持久化到 [_selfPeerId]，后续心跳复用同一标识供
  /// PC 端校验身份。
  DeviceInfo _buildLocalDeviceInfo() {
    var name = '';
    try {
      name = Platform.localHostname;
    } catch (_) {
      name = '';
    }
    if (name.isEmpty) name = 'AndroidDevice';

    _selfPeerId = _generatePeerId();
    return DeviceInfo(
      endpointType: 'phone',
      name: name,
      version: appVersion,
      protocolVersion: transportProtocolVersion,
      peerId: _selfPeerId!,
    );
  }

  /// 生成 8 字节随机数的十进制十六进制串作为会话 peerId。
  String _generatePeerId() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}