/// MusicSync 手机端入口。
library music_sync_app;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'services/config_service.dart';
import 'services/debug_log_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Hive.initFlutter();
    await ConfigService.instance.init();
    await DebugLogService.instance.init();

    final storageGranted = await PermissionService.instance.requestStoragePermission();
    if (!storageGranted) {
      debugPrint('存储权限未授予，扫描功能可能不可用');
      DebugLogService.instance.error('存储权限未授予，扫描功能可能不可用');
    } else {
      DebugLogService.instance.status('存储权限已授予');
    }

    DebugLogService.instance.info('应用启动完成');

    runApp(const MusicSyncApp());
  } catch (e, stackTrace) {
    debugPrint('启动异常: $e');
    debugPrint('堆栈: $stackTrace');
    DebugLogService.instance.error('应用启动失败: $e');
    runApp(const MusicSyncApp());
  }
}