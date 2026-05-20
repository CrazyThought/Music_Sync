/// 常量定义。
const audioExtensions = {
  'mp3', 'flac', 'wav', 'm4a', 'ogg',
  'wma', 'aac', 'opus', 'ape', 'wv',
};

const defaultWorkers = 4;
const largeFileThresholdBytes = 100 * 1024 * 1024;
const chunkHashSizeBytes = 128 * 1024;

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}