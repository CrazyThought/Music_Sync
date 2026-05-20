/// 主页 —— 状态概览卡片。
import 'package:flutter/material.dart';

import '../models/signature.dart';
import '../models/sync_report.dart';
import '../services/config_service.dart';
import '../services/signature_service.dart';
import '../services/scanner_service.dart';
import '../services/diff_service.dart';
import '../services/import_service.dart';
import '../utils/constants.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Signature? _phoneSignature;
  Signature? _pcSignature;
  SyncReport? _report;
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final config = ConfigService.instance.config;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MusicSync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDeviceCard(
            icon: Icons.phone_android,
            title: '本机音乐',
            path: config.musicFolderPath,
            signature: _phoneSignature,
            onScan: _scanPhone,
            isScanning: _isScanning,
          ),
          const SizedBox(height: 12),
          _buildDeviceCard(
            icon: Icons.computer,
            title: 'PC 端特征',
            path: config.importFolderPath,
            signature: _pcSignature,
            onImport: _importPcSignature,
          ),
          const SizedBox(height: 12),
          _buildSyncStatusCard(),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required IconData icon,
    required String title,
    required String path,
    Signature? signature,
    VoidCallback? onScan,
    VoidCallback? onImport,
    bool isScanning = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 28),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text('路径: ${path.isEmpty ? '未设置' : path}',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            if (signature != null) ...[
              const SizedBox(height: 4),
              Text(
                '${signature.scanSummary.totalFiles} 首 | ${formatSize(signature.scanSummary.totalSizeBytes)}',
                style: const TextStyle(fontSize: 15),
              ),
            ],
            const SizedBox(height: 12),
            if (onScan != null)
              FilledButton.icon(
                onPressed: isScanning ? null : onScan,
                icon: Icon(isScanning ? Icons.hourglass_top : Icons.refresh),
                label: Text(isScanning ? '扫描中...' : '扫描本机音乐'),
              ),
            if (onImport != null)
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_open),
                label: const Text('导入 PC 特征文件'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sync, size: 28),
                SizedBox(width: 8),
                Text('同步状态',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (_report != null && _report!.hasChanges) ...[
              _buildStatRow('新增', _report!.added.length, Colors.green),
              _buildStatRow('更新', _report!.updated.length, Colors.blue),
              _buildStatRow('可删除', _report!.removed.length, Colors.red),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/diff', arguments: _report),
                  child: const Text('查看详细差异'),
                ),
              ),
            ] else
              const Text('暂无比较结果，请先导入 PC 特征文件',
                  style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label: '),
          Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Future<void> _scanPhone() async {
    final config = ConfigService.instance.config;
    if (config.musicFolderPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中配置音乐文件夹路径')),
        );
      }
      return;
    }

    setState(() => _isScanning = true);
    try {
      final scanner = ScannerService();
      final sig = await scanner.scanDirectory(config.musicFolderPath);
      setState(() {
        _phoneSignature = sig;
        _isScanning = false;
      });
      _computeDiff();
    } catch (e) {
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }

  Future<void> _importPcSignature() async {
    final result = await Navigator.pushNamed(context, '/import');
    if (result != null && result is Signature) {
      _pcSignature = result as Signature;
      _computeDiff();
    }
    if (mounted) setState(() {});
  }

  void _computeDiff() {
    if (_phoneSignature != null && _pcSignature != null) {
      final diffService = DiffService();
      _report = diffService.compare(_pcSignature!, _phoneSignature!);
      setState(() {});
    }
  }
}