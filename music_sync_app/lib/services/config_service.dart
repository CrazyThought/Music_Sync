/// 配置持久化服务 —— 基于 Hive Box 存储 JSON 配置。
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import 'debug_log_service.dart';

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
    final old = _config.musicFolderPath;
    _config.musicFolderPath = path;
    save();
    _logSettingChange('音乐目录', old, path);
  }

  void updateImportFolder(String path) {
    final old = _config.importFolderPath;
    _config.importFolderPath = path;
    save();
    _logSettingChange('导入目录', old, path);
  }

  void updateTheme(String mode) {
    final old = _config.themeMode;
    _config.themeMode = mode;
    save();
    _logSettingChange('主题模式', old, mode);
  }

  void updateHashComputation(bool enabled) {
    final old = _config.enableHashComputation;
    _config.enableHashComputation = enabled;
    save();
    _logSettingChange('哈希运算', '$old', '$enabled');
  }

  void updateDebugLog(bool enabled) {
    final old = _config.enableDebugLog;
    _config.enableDebugLog = enabled;
    save();
    _logSettingChange('调试日志', '$old', '$enabled');
  }

  void updateAutoDetectMusicFolder(bool enabled) {
    final old = _config.autoDetectMusicFolder;
    _config.autoDetectMusicFolder = enabled;
    save();
    _logSettingChange('自动检测音乐目录', '$old', '$enabled');
  }

  void updateScanExtensions(List<String> extensions) {
    final old = _config.scanExtensions.join(',');
    _config.scanExtensions = List.of(extensions);
    save();
    _logSettingChange('扫描扩展名', old, extensions.join(','));
  }

  /// 记录一次设置变更：输出字段名以及变更前后的值。
  void _logSettingChange(String field, String oldValue, String newValue) {
    DebugLogService.instance.operation('设置变更 - $field: "$oldValue" → "$newValue"');
  }
}