/// 文件条目模型 —— 对应 SIGNATURE_SPEC v2.0 中 files[] 条目。
import 'dart:convert';

class AudioMeta {
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final int? bitrateKbps;

  const AudioMeta({
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    this.bitrateKbps,
  });

  factory AudioMeta.fromJson(Map<String, dynamic> json) {
    return AudioMeta(
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String?,
      durationMs: json['duration_ms'] as int? ?? 0,
      bitrateKbps: json['bitrate_kbps'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'duration_ms': durationMs,
        'bitrate_kbps': bitrateKbps,
      };
}

class FileEntry {
  final String relativePath;
  final int fileSize;
  final int modifiedAt;
  final String contentHash;
  final String contentHashAlgo;
  final AudioMeta audioMeta;
  final String? audioFingerprint;

  const FileEntry({
    required this.relativePath,
    required this.fileSize,
    required this.modifiedAt,
    required this.contentHash,
    this.contentHashAlgo = 'xxh64',
    required this.audioMeta,
    this.audioFingerprint,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      relativePath: json['relative_path'] as String,
      fileSize: json['file_size'] as int,
      modifiedAt: json['modified_at'] as int,
      contentHash: json['content_hash'] as String,
      contentHashAlgo: json['content_hash_algo'] as String? ?? 'xxh64',
      audioMeta: AudioMeta.fromJson(json['audio_meta'] as Map<String, dynamic>),
      audioFingerprint: json['audio_fingerprint'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'relative_path': relativePath,
        'file_size': fileSize,
        'modified_at': modifiedAt,
        'content_hash': contentHash,
        'content_hash_algo': contentHashAlgo,
        'audio_meta': audioMeta.toJson(),
        'audio_fingerprint': audioFingerprint,
      };
}