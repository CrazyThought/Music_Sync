/// 调试日志弹窗 —— 从本地日志文件实时读取并按级别着色展示，支持虚拟列表、
/// 分页加载、导出到自定义目录与一键清空。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/debug_log_entry.dart';
import '../services/debug_log_service.dart';

/// 弹出调试日志弹窗。
Future<void> showDebugLogDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const DebugLogDialog(),
  );
}

/// 调试日志弹窗主体。
///
/// 监听 [DebugLogService] 实现实时刷新；日志从当前会话文件读取（最新在前），
/// 使用 [ListView.builder] 虚拟列表渲染并按页增量加载，避免一次加载过多条目影响性能。
class DebugLogDialog extends StatefulWidget {
  const DebugLogDialog({super.key});

  @override
  State<DebugLogDialog> createState() => _DebugLogDialogState();
}

class _DebugLogDialogState extends State<DebugLogDialog> {
  /// 每页加载的日志条数。
  static const int _pageSize = 200;

  final List<DebugLogEntry> _all = <DebugLogEntry>[];
  int _visible = _pageSize;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    DebugLogService.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    DebugLogService.instance.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('调试日志'),
          const Spacer(),
          TextButton.icon(
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('导出'),
          ),
          TextButton(
            onPressed: () async => DebugLogService.instance.clearCurrent(),
            child: const Text('清空'),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _buildBody(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  /// 根据加载状态与数据构建日志列表或占位提示。
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_all.isEmpty) {
      return const Center(
        child: Text('暂无日志', style: TextStyle(color: Colors.grey)),
      );
    }

    final hasMore = _visible < _all.length;
    return ListView.builder(
      // 末尾追加一项「加载更多」，其余为日志条目。
      itemCount: _visible + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasMore && index == _visible) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() {
                _visible = _all.length < _visible + _pageSize
                    ? _all.length
                    : _visible + _pageSize;
              }),
              child: const Text('加载更多'),
            ),
          );
        }
        return _LogTile(entry: _all[index]);
      },
    );
  }

  /// 重新读取日志文件并刷新列表。
  Future<void> _reload() async {
    final entries = await DebugLogService.instance.readAllNewestFirst();
    if (!mounted) return;
    setState(() {
      _all
        ..clear()
        ..addAll(entries);
      _visible = entries.length < _pageSize ? entries.length : _pageSize;
      _loading = false;
    });
  }

  /// 将当前会话日志内容导出为用户指定路径的 `.log` 文件。
  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final raw = await DebugLogService.instance.readRaw();
      final bytes = utf8.encode(raw);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出调试日志',
        fileName: 'music_sync_debug_${_fileStamp()}.log',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['log'],
      );
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('日志已导出到: $path')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 生成用于导出文件名的紧凑时间戳。
  String _fileStamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

/// 单条日志展示组件。
class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final DebugLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(entry.level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.formattedTime,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withAlpha(38),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.level.label,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.message, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// 根据日志级别返回对应的展示颜色。
  Color _levelColor(DebugLogLevel level) {
    switch (level) {
      case DebugLogLevel.error:
        return Colors.red;
      case DebugLogLevel.operation:
        return Colors.blue;
      case DebugLogLevel.status:
        return Colors.green;
      case DebugLogLevel.info:
        return Colors.grey;
    }
  }
}
