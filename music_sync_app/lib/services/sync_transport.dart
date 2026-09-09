/// 传输通道抽象接口 —— 定义中立的连接能力，供不同通道实现。
///
/// 与 PC 端 `SyncTransport` 语义对齐：只表达「连接 / 断开」能力，
/// 不绑定具体技术，便于后续局域网 / 蓝牙 / USB 等通道多实现并存。
import '../models/device_info.dart';

abstract class SyncTransport {
  /// 建立到指定 URI 的会话连接。
  ///
  /// [uri] 目标连接地址（如二维码携带的配对 URL）。
  Future<DeviceInfo> connect(Uri uri);

  /// 断开当前会话并释放资源。
  Future<void> disconnect();
}