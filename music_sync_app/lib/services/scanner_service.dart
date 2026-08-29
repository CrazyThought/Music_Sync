/// 手机端文件扫描服务。
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/file_entry.dart';
import '../models/signature.dart';
import '../utils/constants.dart';
import 'hash_utils.dart';

class ScannerService {
  static const _largeFileThreshold = 100 * 1024 * 1024; // 100 MB

  Future<Signature> scanDirectory(String rootPath, {bool computeHash = true}) async {
    final stopwatch = Stopwatch()..start();

    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      throw FileSystemException('目录不存在', rootPath);
    }

    final entries = <FileEntry>[];
    debugPrint('扫描开始: $rootPath');
    try {
      final allFiles = await dir.list(recursive: true).toList();
      debugPrint('目录总条目数（含目录和文件）: ${allFiles.length}');
      for (final entity in allFiles) {
        debugPrint('  ${entity is File ? "文件" : "目录"}: ${entity.path}');
      }
    } catch (e) {
      debugPrint('⚠ 无法列出目录内容: $e');
    }
    await _scanDir(dir, dir, entries, computeHash);

    entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));

    final totalSize = entries.fold<int>(0, (sum, e) => sum + e.fileSize);
    final durationMs = stopwatch.elapsedMilliseconds;
    debugPrint('扫描完成，发现音频文件数: ${entries.length}');
    for (final entry in entries) {
      debugPrint('  音频: ${entry.relativePath} (${entry.fileSize} bytes, hash=${entry.contentHash})');
    }

    return Signature(
      formatVersion: '2.0',
      generatedBy: 'MusicSync/App/1.0.0',
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      scanRoot: rootPath,
      scanSummary: ScanSummary(
        totalFiles: entries.length,
        totalSizeBytes: totalSize,
        scanDurationMs: durationMs,
      ),
      files: entries,
      fingerprintAlgorithms: {
        'content': computeHash ? 'xxh3_64' : 'none',
        'audio': 'none',
      },
    );
  }

  Future<void> _scanDir(
    Directory root,
    Directory dir,
    List<FileEntry> result,
    bool computeHash,
  ) async {
    final countBefore = result.length;
    await for (final entity in dir.list(recursive: false)) {
      if (entity is File) {
        final ext = entity.path.split('.').lastOrNull?.toLowerCase() ?? '';
        if (!audioExtensions.contains(ext)) continue;

        final stat = await entity.stat();
        final relativePath = entity.path
            .replaceFirst('${root.path}${Platform.pathSeparator}', '')
            .replaceAll('\\', '/');

        result.add(FileEntry(
          relativePath: relativePath,
          fileSize: stat.size,
          modifiedAt: stat.modified.millisecondsSinceEpoch,
          contentHash: computeHash
              ? await _computeHash(entity.path, stat.size)
              : '',
          contentHashAlgo: computeHash ? 'xxh3_64' : 'none',
          audioMeta: const AudioMeta(
            title: '',
            artist: '',
            durationMs: 0,
          ),
        ));
      } else if (entity is Directory) {
        await _scanDir(root, entity, result, computeHash);
      }
    }
    debugPrint('_scanDir 完成: ${dir.path}, 音频文件: ${result.length - countBefore}');
  }

  Future<String> _computeHash(String filePath, int fileSize) async {
    try {
      final hash = fileSize >= _largeFileThreshold
          ? await computeChunkedHash(filePath, fileSize)
          : await computeXxh64(filePath);
      if (hash.isEmpty) {
        debugPrint('哈希计算返回空: $filePath ($fileSize bytes)');
      }
      return hash;
    } catch (e) {
      debugPrint('哈希计算失败: $filePath ($fileSize bytes), $e');
      return '';
    }
  }
}