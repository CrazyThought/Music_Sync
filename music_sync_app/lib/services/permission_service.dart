/// Android 存储权限请求与状态查询服务。
///
/// 使用 permission_handler 插件管理 Android 存储/媒体权限。
/// 采用单例模式，全局通过 [PermissionService.instance] 访问。
library;

import 'dart:io';

import 'package:permission_handler/permission_handler.dart' as ph;

class PermissionService {
  static final PermissionService _instance = PermissionService._();

  /// 全局单例访问点。
  static PermissionService get instance => _instance;

  PermissionService._();

  /// 异步请求存储权限（读 + 写）。
  ///
  /// Android 13+（SDK 33+）上请求 [ph.Permission.audio]（读取音频文件）；
  /// Android 13 以下则请求 [ph.Permission.storage]（读写外部存储）。
  /// 非 Android 平台始终返回 `true`。
  ///
  /// 返回 `true` 表示已授权，`false` 表示未授权。
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 13+ 请求音频媒体权限
    if (Platform.operatingSystemVersion.contains('Android')) {
      final sdkVersion = _getAndroidSdkVersion();
      if (sdkVersion >= 33) {
        final status = await ph.Permission.audio.request();
        if (status.isGranted) return true;
      }
    }

    // Android 12 及以下请求存储权限（包含读写）
    final status = await ph.Permission.storage.request();

    if (status.isGranted) return true;

    // 权限被永久拒绝，引导用户前往系统设置
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  /// 检查当前是否已有存储权限。
  ///
  /// 非 Android 平台始终返回 `true`。
  ///
  /// 返回 `true` 表示已授权，`false` 表示未授权。
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final status = await ph.Permission.storage.status;
    return status.isGranted;
  }

  /// 打开系统应用设置页面，引导用户手动开启权限。
  ///
  /// 返回 `true` 表示成功打开设置页面，`false` 表示操作失败。
  Future<bool> openAppSettings() {
    return ph.openAppSettings();
  }

  /// 获取 Android SDK 版本号。
  static int _getAndroidSdkVersion() {
    try {
      final version = Platform.operatingSystemVersion;
      final match = RegExp(r'Android (\d+)').firstMatch(version);
      if (match != null) return int.parse(match.group(1)!);
    } catch (_) {}
    return 30; // 默认 Android 11
  }
}