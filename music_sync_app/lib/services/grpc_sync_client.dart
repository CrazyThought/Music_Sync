/// gRPC 数据传输客户端 —— 承载签名拉取与音频文件双向传输。
///
/// 与 PC 端 `services/grpc_transport.py` 对应：
/// - 控制面（配对 / 握手 / 心跳）走 HTTP，由 [QrPairingService] 负责；
/// - 数据面（签名 + 文件）走 gRPC，由本类负责。
///
/// 鉴权：所有 RPC 在 metadata 中携带本机 `peer-id`（握手时生成），与服务端
/// 记录的对端 id 一致才被受理。
///
/// 断点续传：
/// - 下载：以本地 `.musicsync-part` 临时文件长度作为续传偏移；
/// - 上传：调用 [queryUploadedBytes] 查询服务端已接收字节作为续传偏移。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';

import '../generated/musicsync.pb.dart' as pb;
// pbgrpc 会 re-export pb，为避免与本地模型同名冲突，统一加前缀调用
import '../generated/musicsync.pbgrpc.dart' as svc;
import '../models/signature.dart';
import '../utils/constants.dart';
import 'debug_log_service.dart';
import 'hash_utils.dart';
import 'signature_service.dart';

/// 传输进度回调：(已传输字节, 文件总字节)。
typedef TransferProgressCallback = void Function(int transferred, int total);

/// 传输被用户中止时抛出（临时文件保留，供下次续传）。
class TransferCancelledException implements Exception {
  const TransferCancelledException();

  @override
  String toString() => '传输已被用户中止';
}

/// 下载/上传临时文件后缀：未完成传输以该后缀落盘，避免被扫描进音乐库。
const String transferPartSuffix = '.musicsync-part';

/// gRPC 数据传输客户端。
class GrpcSyncClient {
  /// PC 端主机地址。
  final String host;

  /// PC 端 gRPC 端口。
  final int port;

  /// 本机（手机）peerId，作为请求鉴权标识。
  final String peerId;

  /// 分块大小（字节），与 PC 端 GRPC_TRANSFER_CHUNK_SIZE 对齐。
  final int chunkSize;

  ClientChannel? _channel;
  svc.MusicSyncClient? _stub;

  GrpcSyncClient({
    required this.host,
    required this.port,
    required this.peerId,
    this.chunkSize = 256 * 1024,
  });

  /// 数据面是否可用（已建连且端口合法）。
  bool get isAvailable => port > 0 && host.isNotEmpty && peerId.isNotEmpty;

  /// 是否已建立连接。
  bool get isOpen => _stub != null;

  /// 建立 gRPC 连接（幂等）。局域网内使用明文信道。
  void open() {
    if (_stub != null || !isAvailable) return;
    final channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _channel = channel;
    // 鉴权标识统一挂在 stub 上，避免每个调用点重复传参
    _stub = svc.MusicSyncClient(
      channel,
      options: CallOptions(metadata: <String, String>{'peer-id': peerId}),
    );
    DebugLogService.instance.info('gRPC 数据通道已建立: $host:$port');
  }

  /// 关闭连接并释放资源。
  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    _stub = null;
    if (channel != null) {
      await channel.shutdown();
      DebugLogService.instance.info('gRPC 数据通道已关闭');
    }
  }

  svc.MusicSyncClient _requireStub() {
    final stub = _stub;
    if (stub == null) {
      throw StateError('gRPC 数据通道未建立或已关闭');
    }
    return stub;
  }

  // ------------------------------------------------------------------
  // 签名拉取
  // ------------------------------------------------------------------
  /// 拉取 PC 端最新特征签名。
  ///
  /// 服务端以 SIGNATURE_SPEC v2.0 的 JSON 字节整体下发，这里交给
  /// [SignatureService.loadFromString] 解析并做格式/版本/算法校验，
  /// 与「手动导入签名」走完全相同的校验路径。
  Future<Signature> fetchSignature() async {
    final response = await _requireStub().getSignature(
      pb.GetSignatureRequest(),
      options: _callOptions(),
    );
    final signature = await SignatureService().loadFromString(
      utf8.decode(response.json),
    );
    DebugLogService.instance.status(
      '已拉取 PC 特征签名: ${signature.scanSummary.totalFiles} 首',
    );
    return signature;
  }

  // ------------------------------------------------------------------
  // 下载
  // ------------------------------------------------------------------
  /// 下载文件到 [targetPath]，支持断点续传与内容校验。
  ///
  /// 传输过程写入 `targetPath + [transferPartSuffix]` 临时文件，全部接收且
  /// 校验通过后才重命名为正式文件；中断时保留临时文件供下次续传。
  ///
  /// [expectedContentHash] 非空且非 `none` 时，下载完成后本地重算哈希比对，
  /// 不一致则判定失败。
  ///
  /// 返回实际落盘字节数。
  Future<int> downloadFile({
    required String relativePath,
    required String targetPath,
    String? expectedContentHash,
    TransferProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final partPath = '$targetPath$transferPartSuffix';
    final partFile = File(partPath);
    await partFile.parent.create(recursive: true);

    var offset = 0;
    if (await partFile.exists()) {
      offset = await partFile.length();
    }
    DebugLogService.instance.operation(
      '开始下载: $relativePath（续传偏移 $offset）',
    );

    var received = offset;
    var total = 0;
    final sink = partFile.openWrite(mode: FileMode.append);

    try {
      final stream = _requireStub().downloadFile(
        pb.DownloadRequest(relativePath: relativePath, offset: Int64(offset)),
        options: _callOptions(),
      );
      await for (final chunk in stream) {
        if (isCancelled?.call() ?? false) {
          throw const TransferCancelledException();
        }
        if (chunk.data.isNotEmpty) {
          sink.add(chunk.data);
          received = chunk.offset.toInt() + chunk.data.length;
        }
        total = chunk.totalSize.toInt();
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (total > 0 && received < total) {
      throw FileSystemException('下载不完整（$received / $total 字节）', relativePath);
    }

    // 校验：本地重算哈希，与签名中的 content_hash 比对
    if (expectedContentHash != null &&
        expectedContentHash.isNotEmpty &&
        expectedContentHash != 'none') {
      final actual = await _computeFileHash(partPath, received);
      if (actual != expectedContentHash) {
        // 校验失败删除临时文件，避免用损坏数据续传
        try {
          await partFile.delete();
        } on FileSystemException {
          // 临时文件不存在等情况可忽略
        }
        throw FileSystemException(
            '内容校验失败（期望 $expectedContentHash，实际 $actual）', relativePath);
      }
    }

    // 校验通过后落盘为正式文件（覆盖已存在的旧版本）
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    await partFile.rename(targetPath);
    DebugLogService.instance.status('下载完成: $relativePath（$received 字节）');
    return received;
  }

  // ------------------------------------------------------------------
  // 上传
  // ------------------------------------------------------------------
  /// 查询服务端已接收字节数，用于上传断点续传。
  Future<int> queryUploadedBytes(String relativePath) async {
    final response = await _requireStub().getUploadStatus(
      pb.UploadStatusRequest(relativePath: relativePath),
      options: _callOptions(),
    );
    return response.receivedBytes.toInt();
  }

  /// 上传本地文件到 PC 端 [relativePath]，支持断点续传。
  ///
  /// [startOffset] 为续传起始偏移（一般由 [queryUploadedBytes] 得到）。
  /// 返回服务端在接收完成后重算的内容哈希，供调用方比对校验。
  Future<({int bytes, String contentHash})> uploadFile({
    required String relativePath,
    required String localPath,
    int startOffset = 0,
    TransferProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final file = File(localPath);
    final total = await file.length();
    DebugLogService.instance.operation(
      '开始上传: $relativePath（续传偏移 $startOffset / 共 $total 字节）',
    );

    final response = await _requireStub().uploadFile(
      _buildChunkStream(
        relativePath: relativePath,
        file: file,
        total: total,
        startOffset: startOffset,
        onProgress: onProgress,
        isCancelled: isCancelled,
      ),
      options: _callOptions(),
    );
    DebugLogService.instance.status(
      '上传结束: $relativePath（完成=${response.completed}，已收 ${response.receivedBytes} 字节）',
    );
    return (bytes: response.receivedBytes.toInt(), contentHash: response.contentHash);
  }

  /// 构造上传用的分块流：从 [startOffset] 起按 [chunkSize] 逐块产出。
  Stream<pb.FileChunk> _buildChunkStream({
    required String relativePath,
    required File file,
    required int total,
    required int startOffset,
    TransferProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async* {
    // 服务端已收满全部字节（例如上次客户端未收到完成响应就退出了）：
    // 此时无数据可发，但仍需发一个空块让服务端据 relative_path / total_size
    // 触发截断与落盘重命名，否则服务端会因「未收到任何数据块」而拒绝。
    if (startOffset >= total) {
      yield pb.FileChunk(
        relativePath: relativePath,
        offset: Int64(total),
        data: Uint8List(0),
        totalSize: Int64(total),
      );
      return;
    }

    final raf = await file.open();
    try {
      var offset = startOffset;
      await raf.setPosition(offset);
      final buffer = Uint8List(chunkSize);
      while (offset < total) {
        if (isCancelled?.call() ?? false) {
          throw const TransferCancelledException();
        }
        final read = await raf.readInto(buffer);
        if (read <= 0) break;
        yield pb.FileChunk(
          relativePath: relativePath,
          offset: Int64(offset),
          data: buffer.sublist(0, read),
          totalSize: Int64(total),
        );
        offset += read;
        onProgress?.call(offset, total);
      }
    } finally {
      await raf.close();
    }
  }

  // ------------------------------------------------------------------
  // 内部工具
  // ------------------------------------------------------------------
  /// 单次调用的超时设置：局域网传输可能较大，给足超时避免长传输被中断。
  CallOptions _callOptions() =>
      CallOptions(timeout: const Duration(minutes: 10));

  /// 按与扫描器一致的策略计算文件哈希（大文件取首尾分块，小文件全量）。
  Future<String> _computeFileHash(String filePath, int fileSize) {
    if (fileSize >= largeFileThresholdBytes) {
      return computeChunkedHash(filePath, fileSize);
    }
    return computeXxh64(filePath);
  }
}
