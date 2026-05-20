/// MusicSync 手机端入口。
library music_sync_app;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'services/config_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await ConfigService.instance.init();

  final storageGranted = await PermissionService.instance.requestStoragePermission();
  if (!storageGranted) {
    debugPrint('存储权限未授予，扫描功能可能不可用');
  }

  runApp(const MusicSyncApp());
}