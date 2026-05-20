/// 导入 PC 签名页面 —— 从文件选择器或粘贴 JSON 导入。
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/signature.dart';
import '../services/import_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final ImportService _importService = ImportService();
  final TextEditingController _pasteController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入 PC 特征文件')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择文件',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('从文件管理器选择 pc_signature.json'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('选择文件'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('粘贴 JSON',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pasteController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: '在此粘贴 pc_signature.json 的内容...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _pasteJson,
                      icon: const Icon(Icons.paste),
                      label: const Text('导入 JSON'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _isLoading = true);
    final importResult = await _importService.importFromFile(result.files.single.path!);
    setState(() => _isLoading = false);

    if (mounted) {
      if (importResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入成功: ${importResult.signature!.scanSummary.totalFiles} 首')),
        );
        Navigator.pop(context, importResult.signature);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: ${importResult.error}')),
        );
      }
    }
  }

  Future<void> _pasteJson() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴 JSON 内容')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final importResult = await _importService.importFromString(text);
    setState(() => _isLoading = false);

    if (mounted) {
      if (importResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入成功: ${importResult.signature!.scanSummary.totalFiles} 首')),
        );
        Navigator.pop(context, importResult.signature);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: ${importResult.error}')),
        );
      }
    }
  }
}