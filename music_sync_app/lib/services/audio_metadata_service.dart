/// 音频元数据读取服务 —— 封装 Android MediaMetadataRetriever 的 MethodChannel 调用。
///
/// 仅 Android 平台有效；非 Android 或通道不可用时返回 null，
/// 由调用方按兜底规则构造空元数据，保证扫描流程不受影响。
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../models/file_entry.dart';

/// Android 框架（MediaMetadataRetriever）不支持的音频扩展名，跳过原生读取。
const unsupportedAudioExtensions = {'wma', 'ape', 'wv'};

class AudioMetadataService {
  static const MethodChannel _channel =
      MethodChannel('com.example.music_sync_app/audio_metadata');

  /// 读取指定音频文件的原生元数据。
  ///
  /// [filePath] 为设备上的绝对路径。非 Android 平台、通道缺失或读取异常时返回 null。
  /// 返回 Map 的键：title/artist/album/duration_ms/bitrate（字符串，可为 null）。
  static Future<Map<String, dynamic>?> extract(String filePath) async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'extractAudioMeta',
        {'path': filePath},
      );
      if (raw == null) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      // 通道缺失（MissingPluginException）等一律返回 null，由调用方兜底
      return null;
    }
  }
}

/// 依据原生提取结果构造手机端 [AudioMeta]，字段语义与 PC 端 mutagen 对齐。
///
/// [relativePath] 用于标题回退：无标题时使用文件名（去扩展名）。
/// [raw] 为 null（未读取/不支持/失败）时整体回退为空元数据。
AudioMeta buildPhoneAudioMeta({
  required String relativePath,
  Map<String, dynamic>? raw,
}) {
  final stem = _fileStem(relativePath);
  if (raw == null) {
    return AudioMeta(title: stem, artist: '', durationMs: 0);
  }
  final title = _textOrNull(raw['title']) ?? stem;
  final artist = _textOrNull(raw['artist']) ?? '';
  final album = _textOrNull(raw['album']);
  final durationMs = int.tryParse(raw['duration_ms']?.toString() ?? '') ?? 0;
  final bitrateBps = int.tryParse(raw['bitrate']?.toString() ?? '');
  // 仅 mp3/m4a/ogg 在 PC 端有比特率语义；其余（含无损）恒为 null，与 mutagen 对齐
  final bitrateKbps = (bitrateBps != null &&
          _bitrateExtensions.contains(_extensionOf(relativePath)))
      ? bitrateBps ~/ 1000
      : null;
  return AudioMeta(
    title: title,
    artist: artist,
    album: album,
    durationMs: durationMs,
    bitrateKbps: bitrateKbps,
  );
}

/// PC 端 audio_meta 会输出比特率的扩展名集合（对应 mutagen 的 mp3/mp4/oggvorbis 分支）。
const _bitrateExtensions = {'mp3', 'm4a', 'ogg'};

/// 取文件名去掉最后一个扩展名后的兜底标题。
String _fileStem(String relativePath) {
  final name = relativePath.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// 取文件名的小写扩展名（不含点）。
String _extensionOf(String relativePath) {
  final name = relativePath.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
}

/// 将非空文本转为 trim 后的字符串；null 或空白视为 null。
String? _textOrNull(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
