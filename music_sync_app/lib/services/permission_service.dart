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
  /// 优先检查并请求 [ph.Permission.manageExternalStorage]（管理所有文件），
  /// 这是最高级别的存储权限。如果未授予，则在 Android 13+ 上请求音频权限，
  /// Android 13 以下请求传统存储权限。
  /// 非 Android 平台始终返回 `true`。
  ///
  /// 返回 `true` 表示已授权，`false` 表示未授权。
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // 优先请求管理所有文件权限
    final manageStatus = await ph.Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;

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
  /// 优先检查 [ph.Permission.manageExternalStorage]（管理所有文件），
  /// 这是最高级别的存储权限，授予后可以直接读取所有文件。
  /// 非 Android 平台始终返回 `true`。
  ///
  /// 返回 `true` 表示已授权，`false` 表示未授权。
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // 优先检查管理所有文件权限
    if (await ph.Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // Android 13+ 检查音频媒体权限
    if (Platform.operatingSystemVersion.contains('Android')) {
      final sdkVersion = _getAndroidSdkVersion();
      if (sdkVersion >= 33) {
        return ph.Permission.audio.isGranted;
      }
    }

    // Android 12 及以下检查存储权限
    final status = await ph.Permission.storage.status;
    return status.isGranted;
  }

  /// 打开系统应用设置页面，引导用户手动开启权限。
  ///
  /// 返回 `true` 表示成功打开设置页面，`false` 表示操作失败。
  Future<bool> openAppSettings() {
    return ph.openAppSettings();
  }

  /// 获取 Android SDK API 级别。
  static int _getAndroidSdkVersion() {
    try {
      final version = Platform.operatingSystemVersion;
      // 格式通常为 "Android 16 (API 36)" 或 "Android 13 (SDK 33)"
      // 优先匹配 API/SDK 级别
      final apiMatch = RegExp(r'(?:API|SDK)\s*(\d+)').firstMatch(version);
      if (apiMatch != null) return int.parse(apiMatch.group(1)!);
      // 如果没有 API/SDK 信息，匹配 Android 版本号并转换为 SDK 级别
      final androidMatch = RegExp(r'Android\s+(\d+)').firstMatch(version);
      if (androidMatch != null) {
        final androidVersion = int.parse(androidMatch.group(1)!);
        // Android 13 = API 33, Android 14 = API 34, Android 15 = API 35, Android 16 = API 36
        if (androidVersion >= 13) return 20 + androidVersion;
      }
    } catch (_) {}
    return 30; // 默认 Android 11
  }
}
