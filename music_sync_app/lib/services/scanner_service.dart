/// 手机端文件扫描服务。
import 'dart:io';
import 'dart:math';

import '../models/file_entry.dart';
import '../models/signature.dart';
import '../utils/constants.dart';

class ScannerService {
  Future<Signature> scanDirectory(String rootPath) async {
    final stopwatch = Stopwatch()..start();

    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      throw FileSystemException('目录不存在', rootPath);
    }

    final entries = <FileEntry>[];
    await _scanDir(dir, dir, entries);

    entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));

    final totalSize = entries.fold<int>(0, (sum, e) => sum + e.fileSize);
    final durationMs = stopwatch.elapsedMilliseconds;

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
      fingerprintAlgorithms: const {'content': 'xxh64', 'audio': 'none'},
    );
  }

  Future<void> _scanDir(Directory root, Directory dir, List<FileEntry> result) async {
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
          contentHash: '', // 手机端暂不计算xxHash，留待后续
          audioMeta: const AudioMeta(
            title: '',
            artist: '',
            durationMs: 0,
          ),
        ));
      } else if (entity is Directory) {
        await _scanDir(root, entity, result);
      }
    }
  }
}