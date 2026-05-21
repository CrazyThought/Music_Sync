/// 文件哈希工具 —— 与 PC 端 Python xxHash 分块策略一致。
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:xxh3/xxh3.dart';

/// 使用 xxh3 计算整个文件的 64 位哈希值。
///
/// - 文件 ≤ 50MB：一次性读取全文件通过 [xxh3String] 计算，与 PC 端一致
/// - 文件 > 50MB：分块读取（8192 字节），显式拷贝数据避免缓冲区重用
///
/// 返回 16 位小写十六进制字符串，与 PC 端 [compute_xxhash64] 策略一致。
Future<String> computeXxh64(String filePath) async {
  final file = File(filePath);
  const fullReadThreshold = 50 * 1024 * 1024; // 50 MB

  final fileSize = await file.length();
  if (fileSize <= fullReadThreshold) {
    final bytes = await file.readAsBytes();
    final actualBytes = bytes.length;
    debugPrint('computeXxh64: $filePath, 文件大小=$fileSize, 读取字节=$actualBytes');
    if (actualBytes != fileSize) {
      debugPrint('⚠️ 读取字节数与文件大小不匹配！');
    }
    final hash = xxh3String(bytes).padLeft(16, '0');
    debugPrint('computeXxh64 结果: $hash');
    return hash;
  }

  // 大文件：流式读取 + 显式拷贝防缓冲区重用
  final raf = await file.open(mode: FileMode.read);
  try {
    final state = xxh3Stream();
    final buffer = Uint8List(8192);
    int bytesRead;
    while ((bytesRead = await raf.readInto(buffer)) > 0) {
      final chunk = Uint8List.fromList(
        buffer.sublist(0, bytesRead),
      );
      state.update(chunk);
    }
    return state.digestString().padLeft(16, '0');
  } finally {
    await raf.close();
  }
}

/// 使用分块策略计算文件哈希，与 PC 端 [compute_chunked_hash] 策略完全一致。
///
/// - 文件大小 ≤ [chunkSize] * 2 时退化为全量哈希
/// - 大文件取首 [chunkSize] 字节 + 末 [chunkSize] 字节组合计算
///
/// 返回 16 位小写十六进制字符串。
Future<String> computeChunkedHash(
  String filePath,
  int fileSize, {
  int chunkSize = 128 * 1024,
}) async {
  if (fileSize <= chunkSize * 2) {
    return computeXxh64(filePath);
  }

  final file = File(filePath);
  final raf = await file.open(mode: FileMode.read);
  try {
    final state = xxh3Stream();

    // 首部 chunkSize 字节
    final firstChunk = await raf.read(chunkSize);
    state.update(firstChunk);

    // 尾部 chunkSize 字节（seek 到末尾前 chunkSize 处）
    await raf.setPosition(max(0, fileSize - chunkSize));
    final lastChunk = await raf.read(chunkSize);
    state.update(lastChunk);

    return state.digestString().padLeft(16, '0');
  } finally {
    await raf.close();
  }
}
