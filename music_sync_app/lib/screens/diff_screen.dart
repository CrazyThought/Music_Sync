/// 差异展示页面 —— 分类展示新增/更新/删除/未变。
import 'package:flutter/material.dart';

import '../models/sync_report.dart';
import '../models/file_entry.dart';
import '../models/updated_file_pair.dart';
import '../utils/constants.dart';

class DiffScreen extends StatefulWidget {
  const DiffScreen({super.key});

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  SyncReport? _report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final report = ModalRoute.of(context)?.settings.arguments;
    if (report is SyncReport) {
      _report = report;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Scaffold(
      appBar: AppBar(title: const Text('差异详情')),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatChip('新增', report?.added.length ?? 0, Colors.green),
                  _buildStatChip('更新', report?.updated.length ?? 0, Colors.blue),
                  _buildStatChip('删除', report?.removed.length ?? 0, Colors.red),
                  _buildStatChip('未变', report?.unchanged ?? 0, Colors.grey),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: '新增'),
                Tab(text: '更新'),
                Tab(text: '可删除'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildFileList(report?.added ?? [], Colors.green),
                  _buildUpdatedList(report?.updated ?? []),
                  _buildFileList(report?.removed ?? [], Colors.red),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Column(
      children: [
        Text('$count',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(color: Colors.grey[400])),
      ],
    );
  }

  Widget _buildFileList(List<FileEntry> files, Color color) {
    if (files.isEmpty) {
      return const Center(child: Text('暂无数据', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final entry = files[index];
        return ListTile(
          leading: Icon(Icons.music_note, color: color),
          title: Text(entry.audioMeta.title.isNotEmpty
              ? '${entry.audioMeta.title} - ${entry.audioMeta.artist}'
              : entry.relativePath.split('/').last),
          subtitle: Text('${entry.relativePath}\n${formatSize(entry.fileSize)}'),
          isThreeLine: true,
        );
      },
    );
  }

  Widget _buildUpdatedList(List<UpdatedFilePair> items) {
    if (items.isEmpty) {
      return const Center(child: Text('没有需要更新的文件'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final pair = items[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            title: Text(pair.relativePath, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '手机端: ${_formatSize(pair.phoneFile.fileSize)} | ${_formatDate(pair.phoneFile.modifiedAt)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                Text(
                  'PC 端: ${_formatSize(pair.pcFile.fileSize)} | ${_formatDate(pair.pcFile.modifiedAt)}',
                  style: const TextStyle(color: Color(0xFF1976D2), fontSize: 12),
                ),
              ],
            ),
            leading: const Icon(Icons.update, color: Color(0xFF1976D2)),
          ),
        );
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(int msSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}