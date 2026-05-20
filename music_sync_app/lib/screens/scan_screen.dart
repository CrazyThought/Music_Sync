/// 扫描进度页 —— 显示手机端扫描进度。
import 'package:flutter/material.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描本机音乐')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('正在扫描音乐文件夹...'),
            SizedBox(height: 8),
            Text('请稍候', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}