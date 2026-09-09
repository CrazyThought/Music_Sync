/// 设备元信息模型 —— 双端握手交换的身份与协议版本信息。
///
/// 与 PC 端 `DeviceInfo` 对齐，字段为 JSON 的 snake_case 命名。
class DeviceInfo {
  final String endpointType;
  final String name;
  final String version;
  final int protocolVersion;
  final String peerId;

  const DeviceInfo({
    required this.endpointType,
    required this.name,
    required this.version,
    required this.protocolVersion,
    required this.peerId,
  });

  /// 从握手响应 JSON 构造。
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      endpointType: json['endpoint_type'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      protocolVersion: json['protocol_version'] as int? ?? 0,
      peerId: json['peer_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'endpoint_type': endpointType,
        'name': name,
        'version': version,
        'protocol_version': protocolVersion,
        'peer_id': peerId,
      };
}