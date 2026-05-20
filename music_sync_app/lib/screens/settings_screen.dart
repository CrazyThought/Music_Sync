/// 设置页面 —— 音乐目录、导入目录、扫描参数配置。
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/config_service.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _musicController = TextEditingController();
  final _importController = TextEditingController();
  bool _autoDetect = true;

  @override
  void initState() {
    super.initState();
    final config = ConfigService.instance.config;
    _musicController.text = config.musicFolderPath;
    _importController.text = config.importFolderPath;
    _autoDetect = config.autoDetectMusicFolder;
  }

  @override
  void dispose() {
    _musicController.dispose();
    _importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMusicFolderSection(),
          const SizedBox(height: 12),
          _buildImportFolderSection(),
          const SizedBox(height: 12),
          _buildScanSettingsSection(),
          const SizedBox(height: 12),
          _buildAppearanceSection(),
          const SizedBox(height: 12),
          _buildAboutSection(),
        ],
      ),
    );
  }

  Widget _buildMusicFolderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.phone_android, size: 22),
                SizedBox(width: 8),
                Text('本机音乐目录',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _musicController,
              decoration: InputDecoration(
                labelText: '音乐文件夹路径',
                hintText: '/storage/emulated/0/Music',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickMusicFolder,
                ),
              ),
              onChanged: (v) {
                ConfigService.instance.updateMusicFolder(v);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('自动检测音乐目录'),
              subtitle: const Text('启动时自动扫描常见位置'),
              value: _autoDetect,
              onChanged: (v) {
                setState(() => _autoDetect = v);
                ConfigService.instance.config.autoDetectMusicFolder = v;
                ConfigService.instance.save();
              },
              dense: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportFolderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.computer, size: 22),
                SizedBox(width: 8),
                Text('PC 签名导入',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _importController,
              decoration: InputDecoration(
                labelText: '默认导入目录',
                hintText: '/storage/emulated/0/Download/Sync',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickImportFolder,
                ),
              ),
              onChanged: (v) {
                ConfigService.instance.updateImportFolder(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanSettingsSection() {
    final config = ConfigService.instance.config;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune, size: 22),
                SizedBox(width: 8),
                Text('扫描设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: audioExtensions.map((ext) {
                final selected = config.scanExtensions.contains(ext);
                return FilterChip(
                  label: Text(ext),
                  selected: selected,
                  onSelected: (v) {
                    if (v) {
                      config.scanExtensions.add(ext);
                    } else {
                      config.scanExtensions.remove(ext);
                    }
                    ConfigService.instance.save();
                    setState(() {});
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection() {
    final config = ConfigService.instance.config;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.palette, size: 22),
                SizedBox(width: 8),
                Text('外观',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dark', label: Text('深色')),
                ButtonSegment(value: 'light', label: Text('浅色')),
                ButtonSegment(value: 'system', label: Text('跟随系统')),
              ],
              selected: {config.themeMode},
              onSelectionChanged: (v) {
                config.themeMode = v.first;
                ConfigService.instance.save();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 22),
                SizedBox(width: 8),
                Text('关于',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('版本: 1.0.0'),
            const SizedBox(height: 4),
            const Text('签名格式: 2.0 | 哈希: xxh64'),
            const SizedBox(height: 4),
            const Text('扫描引擎: 2.0'),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMusicFolder() async {
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要存储权限才能选择文件夹')),
        );
      }
      return;
    }

    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      _musicController.text = result;
      ConfigService.instance.updateMusicFolder(result);
    }
  }

  Future<void> _pickImportFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      _importController.text = result;
      ConfigService.instance.updateImportFolder(result);
    }
  }
}