/// 扫码配对页 —— 调起相机扫描二维码并完成局域网握手。
///
/// 扫描到携带配对 URL 的二维码后，调用 [QrPairingService.connect] 完成
/// 握手，成功则展示对端 [DeviceInfo]，可返回或关闭页面。
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/device_info.dart';
import '../services/connection_service.dart';
import '../services/debug_log_service.dart';
import '../services/qr_pairing_service.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final QrPairingService _pairingService = QrPairingService();

  bool _connecting = false;
  DeviceInfo? _peerInfo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 请求相机权限，未授予时给出提示。
  Future<void> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _error = '未授予相机权限，无法扫码');
    }
  }

  /// 处理扫码结果：解析 URL 并发起握手。
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_connecting || _peerInfo != null) return;

    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || raw.isEmpty) return;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'http' || uri.path != '/pair') {
      // 非配对二维码，忽略并继续
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      final peer = await _pairingService.connect(uri);
      DebugLogService.instance.status('扫码连接成功: ${peer.endpointType} ${peer.name}');
      if (!mounted) return;
      setState(() => _peerInfo = peer);
      // 写入全局连接状态，供主页连接卡片实时展示
      ConnectionService.instance.onConnected(peer);
    } catch (e) {
      DebugLogService.instance.error('扫码连接失败: $e');
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '连接失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码连接 PC')),
      body: Stack(
        children: [
          if (_error == null)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _ensureCameraPermission();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (_peerInfo != null)
            _buildResultOverlay(_peerInfo!),
          if (_connecting)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  /// 握手成功后的对端信息覆盖层。
  Widget _buildResultOverlay(DeviceInfo peer) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              const Text('连接成功',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('设备类型: ${peer.endpointType}'),
              Text('设备名称: ${peer.name}'),
              Text('版本: ${peer.version}'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, peer),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}