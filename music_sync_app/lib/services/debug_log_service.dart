/// 调试日志服务 —— 全局单例，将日志追加写入本地文件。
///
/// 每次应用启动时在 `logs/` 子目录下新建一个以时间戳命名的日志文件，
/// 不在内存中缓存日志条目；日志弹窗打开时实时从文件读取并展示。
/// 启动时会自动清理超过 7 天的旧日志文件。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/debug_log_entry.dart';

class DebugLogService extends ChangeNotifier {
  static final DebugLogService _instance = DebugLogService._();

  /// 全局单例访问点。
  static DebugLogService get instance => _instance;

  DebugLogService._();

  /// 旧日志保留天数，超过后启动时自动清理。
  static const int retentionDays = 7;

  bool _initialized = false;
  File? _currentFile;

  /// 是否已完成初始化。
  bool get isInitialized => _initialized;

  /// 当前会话日志文件的绝对路径（未初始化时为 null）。
  String? get currentLogFilePath => _currentFile?.path;

  /// 初始化日志服务，创建 `logs/` 目录与当前会话日志文件。
  ///
  /// [logDir] 用于指定日志根目录（测试时传入临时目录）；未传时使用
  /// 应用支持目录下的 `logs/` 子目录。初始化会清理超过 [retentionDays] 的旧文件。
  Future<void> init({Directory? logDir}) async {
    if (_initialized) return;

    final base = logDir ?? await getApplicationSupportDirectory();
    final logsDir = Directory(p.join(base.path, 'logs'));
    await logsDir.create(recursive: true);
    await _cleanupOldLogs(logsDir);

    _currentFile = File(p.join(logsDir.path, 'log_${_fileTimestamp(DateTime.now())}.log'));
    _initialized = true;

    info('日志服务已启动，会话文件: ${_currentFile!.path}');
  }

  /// 记录一条「状态」级别日志。
  void status(String message) => _write(DebugLogLevel.status, message);

  /// 记录一条「操作」级别日志。
  void operation(String message) => _write(DebugLogLevel.operation, message);

  /// 记录一条「报错」级别日志。
  void error(String message) => _write(DebugLogLevel.error, message);

  /// 记录一条「信息」级别日志。
  void info(String message) => _write(DebugLogLevel.info, message);

  /// 清空当前会话日志文件内容。
  Future<void> clearCurrent() async {
    final file = _currentFile;
    if (file == null) return;

    file.writeAsStringSync('');
    notifyListeners();
  }

  /// 读取当前会话日志文件的原始文本内容。
  Future<String> readRaw() async {
    final file = _currentFile;
    if (file == null) return '';
    if (!await file.exists()) return '';
    return file.readAsStringSync();
  }

  /// 读取当前会话全部日志条目，并按时间倒序（最新在前）返回。
  Future<List<DebugLogEntry>> readAllNewestFirst() async {
    final raw = await readRaw();
    if (raw.isEmpty) return const [];

    final entries = <DebugLogEntry>[];
    for (final line in const LineSplitter().convert(raw)) {
      final entry = DebugLogEntry.tryParse(line);
      if (entry != null) entries.add(entry);
    }
    return entries.reversed.toList();
  }

  /// 关闭日志服务（当前实现无句柄需要释放，保留以便与调用方/测试解耦）。
  Future<void> close() async {}

  /// 供测试重置单例状态，避免用例间相互影响。
  @visibleForTesting
  Future<void> resetForTesting() async {
    await close();
    _initialized = false;
    _currentFile = null;
  }

  /// 追加一条日志并通知监听者；未初始化时静默丢弃。
  ///
  /// 采用同步追加写入（不强制 fsync），保证写入顺序且数据即时进入页缓存供读取，
  /// 无需维护 IO 流，避免大目录扫描时频繁落盘影响性能。
  void _write(DebugLogLevel level, String message) {
    final file = _currentFile;
    if (file == null) return;

    final entry = DebugLogEntry(timestamp: DateTime.now(), level: level, message: message);
    file.writeAsStringSync('${entry.format()}\n', mode: FileMode.append);
    notifyListeners();
  }

  /// 清理 [logsDir] 中超过 [retentionDays] 未修改的 `.log` 文件。
  Future<void> _cleanupOldLogs(Directory logsDir) async {
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    await for (final entity in logsDir.list()) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.log') continue;

      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // 单个旧文件删除失败不应阻断启动。
        }
      }
    }
  }

  /// 生成用于日志文件名的时间戳：`yyyyMMdd_HHmmss`。
  String _fileTimestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
