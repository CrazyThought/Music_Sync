/// MusicSync 手机端入口 - 临时简化版本用于排查闪退。
library music_sync_app;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Hive.initFlutter();

    runApp(const MusicSyncApp());
  } catch (e, stackTrace) {
    debugPrint('启动异常: $e');
    debugPrint('堆栈: $stackTrace');
    runApp(const MusicSyncApp());
  }
}
