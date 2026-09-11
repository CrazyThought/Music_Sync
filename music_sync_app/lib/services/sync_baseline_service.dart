/// 同步基线服务 —— 持久化「上次同步成功后的签名快照」。
///
/// 双向同步需要三方比较（基线 B / PC 当前 P / 手机当前 M）才能判断「谁改了」，
/// 因此每次同步完成后都要把双方达成一致的状态写入基线，供下次比较使用。
///
/// 基线不会收录「未达成一致」的条目（未决冲突、仅提示的删除项、传输失败项），
/// 这样它们会在下次同步时重新出现，避免被静默遗忘。
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/signature.dart';
import 'debug_log_service.dart';

class SyncBaselineService {
  static final SyncBaselineService instance = SyncBaselineService._();
  SyncBaselineService._();

  static const _boxName = 'sync_baseline';
  static const _baselineKey = 'signature';

  Box<String>? _box;

  /// 初始化 Hive Box（应用启动时调用一次）。
  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// 读取基线签名；不存在或解析失败时返回 null。
  Future<Signature?> load() async {
    final box = _box;
    if (box == null) return null;
    final raw = box.get(_baselineKey);
    if (raw == null) return null;
    try {
      return Signature.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      DebugLogService.instance.error('同步基线解析失败，已忽略: $e');
      return null;
    }
  }

  /// 写入基线签名。
  Future<void> save(Signature signature) async {
    final box = _box;
    if (box == null) return;
    await box.put(_baselineKey, jsonEncode(signature.toJson()));
    DebugLogService.instance.info('同步基线已更新: ${signature.files.length} 条');
  }

  /// 清空基线（下次同步按首次同步处理）。
  Future<void> clear() async {
    final box = _box;
    if (box == null) return;
    await box.delete(_baselineKey);
  }
}
