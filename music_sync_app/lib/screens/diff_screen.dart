/// 差异展示页面 —— 分类展示新增/更新/删除/未变。
import 'package:flutter/material.dart';

import '../models/sync_report.dart';
import '../models/file_entry.dart';
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatChip('新增', report?.added.length ?? 0, Colors.green),
              _buildStatChip('更新', report?.updated.length ?? 0, Colors.blue),
              _buildStatChip('删除', report?.removed.length ?? 0, Colors.red),
              _buildStatChip('未变', report?.unchanged ?? 0, Colors.grey),
            ],
          ),
          const SizedBox(height: 16),
          DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: '新增'),
                    Tab(text: '更新'),
                    Tab(text: '可删除'),
                  ],
                ),
                SizedBox(
                  height: 400,
                  child: TabBarView(
                    children: [
                      _buildFileList(report?.added ?? [], Colors.green),
                      _buildFileList(report?.updated ?? [], Colors.blue),
                      _buildFileList(report?.removed ?? [], Colors.red),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
}