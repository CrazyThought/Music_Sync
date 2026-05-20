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

  /// 异步请求存储权限。
  ///
  /// Android 13+（SDK 33+）上 [ph.Permission.storage] 会自动映射为细粒度媒体权限；
  /// Android 13 以下则请求传统的存储权限。
  /// 非 Android 平台始终返回 `true`。
  ///
  /// 返回 `true` 表示已授权，`false` 表示未授权。
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

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
}