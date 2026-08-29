/// 配置持久化服务 —— 基于 Hive Box 存储 JSON 配置。
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/app_config.dart';

class ConfigService extends ChangeNotifier {
  static final ConfigService _instance = ConfigService._();
  static ConfigService get instance => _instance;
  ConfigService._();

  static const _boxName = 'app_config';
  static const _configKey = 'current';

  Box<String>? _box;
  AppConfig _config = AppConfig();

  AppConfig get config => _config;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    final jsonStr = _box!.get(_configKey);
    if (jsonStr != null) {
      try {
        _config = AppConfig.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      } catch (_) {
        _config = AppConfig();
      }
    }
  }

  Future<void> save() async {
    if (_box == null) return;
    await _box!.put(_configKey, jsonEncode(_config.toJson()));
    notifyListeners();
  }

  void updateMusicFolder(String path) {
    _config.musicFolderPath = path;
    save();
  }

  void updateImportFolder(String path) {
    _config.importFolderPath = path;
    save();
  }

  void updateTheme(String mode) {
    _config.themeMode = mode;
    save();
  }

  void updateHashComputation(bool enabled) {
    _config.enableHashComputation = enabled;
    save();
  }

  void updateDebugLog(bool enabled) {
    _config.enableDebugLog = enabled;
    save();
  }
}