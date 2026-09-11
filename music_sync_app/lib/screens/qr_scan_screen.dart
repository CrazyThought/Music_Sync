/// 扫码配对页 —— 调起相机扫描二维码并完成局域网握手。
///
/// 扫描到携带配对 URL 的二维码后，调用 [QrPairingService.connect] 完成
/// 握手，成功则展示对端 [DeviceInfo]，可返回或关闭页面。
///
/// 支持实时相机扫码与从相册选图静态解码两条入口，二者复用同一握手逻辑。
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
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
  bool _analyzingImage = false;
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

  /// 处理相机实时识别结果，转发给统一的握手入口。
  Future<void> _onDetect(BarcodeCapture capture) async {
    // 图片解码期间暂停相机识别，避免与静态解码并发握手
    if (_analyzingImage) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    await _handleRawValue(raw);
  }

  /// 处理二维码原始内容：校验 URL 并发起握手（相机与图片扫码共用）。
  ///
  /// 返回 [false] 表示内容不是合法的配对二维码（未发起握手）。
  Future<bool> _handleRawValue(String? raw) async {
    if (_connecting || _peerInfo != null) return false;
    if (raw == null || raw.isEmpty) return false;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'http' || uri.path != '/pair') {
      return false;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      final peer = await _pairingService.connect(uri);
      DebugLogService.instance.status('扫码连接成功: ${peer.endpointType} ${peer.name}');
      if (!mounted) return true;
      setState(() => _peerInfo = peer);
      // 写入全局连接状态，供主页连接卡片实时展示，并由其启动心跳保活
      ConnectionService.instance.onConnected(peer, _pairingService);
    } catch (e) {
      DebugLogService.instance.error('扫码连接失败: $e');
      if (!mounted) return true;
      setState(() {
        _connecting = false;
        _error = '连接失败: $e';
      });
    }
    return true;
  }

  /// 从相册选图并静态解码二维码。
  Future<void> _pickImageAndScan() async {
    if (_connecting || _analyzingImage) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;

    setState(() {
      _analyzingImage = true;
      _error = null;
    });

    BarcodeCapture? capture;
    try {
      capture = await _controller.analyzeImage(path);
    } on UnsupportedError {
      if (mounted) _showSnack('当前环境不支持图片识别');
      return;
    } catch (e) {
      DebugLogService.instance.error('图片识别失败: $e');
      if (mounted) _showSnack('图片识别失败: $e');
      return;
    } finally {
      if (mounted) setState(() => _analyzingImage = false);
    }

    if (!mounted) return;
    if (capture == null || capture.barcodes.isEmpty) {
      _showSnack('未识别到有效二维码');
      return;
    }

    final handled = await _handleRawValue(capture.barcodes.first.rawValue);
    if (!handled) {
      _showSnack('未识别到有效二维码');
    }
  }

  /// 短暂提示框，用于图片扫码等不改变页面主状态的反馈。
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码连接 PC'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: '从相册选择二维码图片',
            onPressed: _pickImageAndScan,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error == null)
            _buildScanner()
          else
            _buildError(),
          if (_peerInfo != null) _buildResultOverlay(_peerInfo!),
          if (_connecting || _analyzingImage)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  /// 相机扫码视图：叠加取景框遮罩并限制识别区域。
  Widget _buildScanner() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // 方形取景框，边长取可用区域的 70%，居中
        final side = math.min(size.width, size.height) * 0.7;
        final scanWindow = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: side,
          height: side,
        );
        return MobileScanner(
          controller: _controller,
          scanWindow: scanWindow,
          onDetect: _onDetect,
          overlayBuilder: (context, constraints) => CustomPaint(
            painter: _ScanOverlayPainter(scanWindow: scanWindow),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  /// 相机不可用（未授权）时的提示视图。
  Widget _buildError() {
    return Center(
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

/// 取景框遮罩绘制器：四周半透明遮罩 + 中间挖空取景框 + 白色边框。
class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.scanWindow});

  /// 取景框矩形（与 [MobileScanner.scanWindow] 同一坐标系，保证视觉与识别一致）。
  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(scanWindow, const Radius.circular(12));
    // 先铺满半透明遮罩，再用 BlendMode.clear 挖出取景框透明区域
    canvas
      ..saveLayer(Offset.zero & size, Paint())
      ..drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x80000000),
      )
      ..drawRRect(cutout, Paint()..blendMode = BlendMode.clear)
      ..restore()
      // 绘制取景框白色边框
      ..drawRRect(
        cutout,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter oldDelegate) =>
      oldDelegate.scanWindow != scanWindow;
}