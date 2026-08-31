/// 主页 —— 状态概览卡片。
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/signature.dart';
import '../models/sync_report.dart';
import '../services/config_service.dart';
import '../services/debug_log_service.dart';
import '../services/scanner_service.dart';
import '../services/diff_service.dart';
import '../services/permission_service.dart';
import '../utils/constants.dart';
import '../widgets/debug_log_dialog.dart';

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
  bool _isExporting = false;
  ScanProgress? _scanProgress;

  @override
  Widget build(BuildContext context) {
    final config = ConfigService.instance.config;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MusicSync'),
        actions: [
          if (config.enableDebugLog)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              tooltip: '调试日志',
              onPressed: () => showDebugLogDialog(context),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () =>
                Navigator.pushNamed(context, '/settings').then((_) => setState(() {})),
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
            isExporting: _isExporting,
            scanProgress: _scanProgress,
            onExport: (_phoneSignature != null && _phoneSignature!.scanSummary.totalFiles > 0)
                ? _exportPhoneSignature
                : null,
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
    VoidCallback? onExport,
    bool isScanning = false,
    bool isExporting = false,
    ScanProgress? scanProgress,
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
            if (isScanning && scanProgress != null) ...[
              const SizedBox(height: 12),
              if (scanProgress.phase == ScanPhase.counting)
                const LinearProgressIndicator()
              else
                LinearProgressIndicator(value: scanProgress.progress),
              const SizedBox(height: 8),
              Text(
                scanProgress.phase == ScanPhase.counting
                    ? '正在统计文件总数...'
                    : '正在扫描 ${scanProgress.completed}/${scanProgress.total}：${scanProgress.currentFile}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (onImport != null)
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_open),
                label: const Text('导入 PC 特征文件'),
              ),
            if (onExport != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: isExporting ? null : onExport,
                  icon: Icon(isExporting ? Icons.hourglass_top : Icons.file_download),
                  label: Text(isExporting ? '导出中...' : '导出特征文件'),
                ),
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

    final hasPermission = await PermissionService.instance.hasStoragePermission();
    if (!hasPermission) {
      final granted = await PermissionService.instance.requestStoragePermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('需要存储权限才能扫描音乐'),
              action: SnackBarAction(
                label: '前往设置',
                onPressed: () => PermissionService.instance.openAppSettings(),
              ),
            ),
          );
        }
        return;
      }
    }

    DebugLogService.instance.operation('开始扫描本机音乐: ${config.musicFolderPath}');
    setState(() {
      _isScanning = true;
      _scanProgress = null;
    });
    try {
      final scanner = ScannerService();
      final sig = await scanner.scanDirectory(
        config.musicFolderPath,
        computeHash: config.enableHashComputation,
        onProgress: (progress) {
          if (mounted) setState(() => _scanProgress = progress);
        },
      );
      DebugLogService.instance.status('扫描完成: 共 ${sig.scanSummary.totalFiles} 首');
      setState(() {
        _phoneSignature = sig;
        _isScanning = false;
        _scanProgress = null;
      });
      _computeDiff();
    } catch (e) {
      DebugLogService.instance.error('扫描失败: $e');
      setState(() {
        _isScanning = false;
        _scanProgress = null;
      });
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
      DebugLogService.instance.operation('导入 PC 特征文件完成，开始差异比较');
      _computeDiff();
    }
    if (mounted) setState(() {});
  }

  void _computeDiff() {
    if (_phoneSignature != null && _pcSignature != null) {
      final diffService = DiffService();
      _report = diffService.compare(_pcSignature!, _phoneSignature!);
      DebugLogService.instance.status(
        '差异比较完成: 新增 ${_report!.added.length} / 更新 ${_report!.updated.length} / 可删除 ${_report!.removed.length} / 未变 ${_report!.unchanged}',
      );
      setState(() {});
    }
  }

  Future<void> _exportPhoneSignature() async {
    final sig = _phoneSignature;
    if (sig == null) return;

    DebugLogService.instance.operation('开始导出特征文件');
    setState(() => _isExporting = true);
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(sig.toJson());
      final jsonBytes = utf8.encode(jsonStr);

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存特征文件',
        fileName: 'phone_signature.json',
        bytes: jsonBytes,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath != null && mounted) {
        DebugLogService.instance.status('特征文件导出成功: $outputPath');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('特征文件已导出到: $outputPath')),
        );
      }
      if (mounted) {
        setState(() => _isExporting = false);
      }
    } catch (e) {
      DebugLogService.instance.error('特征文件导出失败: $e');
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }
}