/// 特征文件模型 —— 对应 SIGNATURE_SPEC v2.0。
import 'file_entry.dart';

class ScanSummary {
  final int totalFiles;
  final int totalSizeBytes;
  final int scanDurationMs;

  const ScanSummary({
    required this.totalFiles,
    required this.totalSizeBytes,
    required this.scanDurationMs,
  });

  factory ScanSummary.fromJson(Map<String, dynamic> json) {
    return ScanSummary(
      totalFiles: json['total_files'] as int,
      totalSizeBytes: json['total_size_bytes'] as int,
      scanDurationMs: json['scan_duration_ms'] as int,
    );
  }
}

class Signature {
  final String formatVersion;
  final String generatedBy;
  final int generatedAt;
  final String scanRoot;
  final ScanSummary scanSummary;
  final List<FileEntry> files;
  final Map<String, String> fingerprintAlgorithms;

  const Signature({
    required this.formatVersion,
    required this.generatedBy,
    required this.generatedAt,
    required this.scanRoot,
    required this.scanSummary,
    required this.files,
    required this.fingerprintAlgorithms,
  });

  factory Signature.fromJson(Map<String, dynamic> json) {
    final fileList = (json['files'] as List<dynamic>)
        .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    final algoMap = <String, String>{};
    (json['fingerprint_algorithms'] as Map<String, dynamic>?)?.forEach((k, v) {
      algoMap[k] = v as String;
    });

    return Signature(
      formatVersion: json['format_version'] as String,
      generatedBy: json['generated_by'] as String,
      generatedAt: json['generated_at'] as int,
      scanRoot: json['scan_root'] as String,
      scanSummary: ScanSummary.fromJson(json['scan_summary'] as Map<String, dynamic>),
      files: fileList,
      fingerprintAlgorithms: algoMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'format_version': formatVersion,
        'generated_by': generatedBy,
        'generated_at': generatedAt,
        'scan_root': scanRoot,
        'scan_summary': {
          'total_files': scanSummary.totalFiles,
          'total_size_bytes': scanSummary.totalSizeBytes,
          'scan_duration_ms': scanSummary.scanDurationMs,
        },
        'files': files.map((e) => e.toJson()).toList(),
        'fingerprint_algorithms': fingerprintAlgorithms,
      };
}