/// 调试日志条目模型 —— 记录一条调试日志的级别、时间与内容，并支持行格式化与解析。
///
/// 日志以单行文本持久化到本地文件，格式固定为 `[yyyy-MM-dd HH:mm:ss][级别] 内容`，
/// 便于后续按行读取、解析并着色展示。
library;

/// 调试日志级别。
///
/// 用于在日志弹窗中区分不同类别的信息，便于快速理解与定位问题：
/// - [status]：状态，描述某一步骤成功完成的概要结果。
/// - [operation]：操作，描述正在执行的用户操作。
/// - [error]：报错，描述失败原因，弹窗中高亮显示。
/// - [info]：信息，补充说明类的一般信息。
enum DebugLogLevel {
  status('状态'),
  operation('操作'),
  error('报错'),
  info('信息');

  const DebugLogLevel(this.label);

  /// 级别的中文显示名。
  final String label;

  /// 根据中文标签反查级别，找不到时返回 null。
  static DebugLogLevel? fromLabel(String label) {
    for (final level in DebugLogLevel.values) {
      if (level.label == label) return level;
    }
    return null;
  }
}

/// 一条调试日志。
class DebugLogEntry {
  /// 日志产生时间。
  final DateTime timestamp;

  /// 日志级别。
  final DebugLogLevel level;

  /// 日志内容。
  final String message;

  const DebugLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  /// 格式化为 `HH:mm:ss` 的显示时间。
  String get formattedTime {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}';
  }

  /// 生成用于写入日志文件的一行文本，格式为 `[yyyy-MM-dd HH:mm:ss][级别] 内容`。
  String format() => '[${_fullTimestamp()}][${level.label}] $message';

  /// 从一行日志文本解析回条目，解析失败时返回 null。
  ///
  /// 行格式固定为 `[yyyy-MM-dd HH:mm:ss][级别] 内容`，其中「级别」为 [DebugLogLevel.label]，
  /// 级别标签后需紧跟一个空格再跟内容，内容中允许出现任意字符（含方括号）。
  static DebugLogEntry? tryParse(String line) {
    // 定位第一个时间戳闭合括号。
    final firstClose = line.indexOf(']');
    if (firstClose <= 0 || line[0] != '[') return null;
    final tsStr = line.substring(1, firstClose);

    // 级别标签必须紧跟在时间戳之后，形如 `][级别]`。
    final secondOpen = line.indexOf('[', firstClose + 1);
    if (secondOpen != firstClose + 1) return null;
    final secondClose = line.indexOf(']', secondOpen + 1);
    if (secondClose < 0) return null;
    final levelLabel = line.substring(secondOpen + 1, secondClose);

    // 级别标签后需紧跟一个空格，剩余部分为日志内容。
    if (secondClose + 1 >= line.length || line[secondClose + 1] != ' ') return null;
    final message = line.substring(secondClose + 2);

    final timestamp = DateTime.tryParse(tsStr);
    final level = DebugLogLevel.fromLabel(levelLabel);
    if (timestamp == null || level == null) return null;

    return DebugLogEntry(timestamp: timestamp, level: level, message: message);
  }

  /// 生成 `yyyy-MM-dd HH:mm:ss` 的完整时间戳，用于落盘。
  String _fullTimestamp() {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${timestamp.year}-${two(timestamp.month)}-${two(timestamp.day)} '
        '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}';
  }
}
