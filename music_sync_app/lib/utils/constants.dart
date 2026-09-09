/// 常量定义。

/// 应用版本号（与 pubspec 版本对齐），用于双端握手交换。
const appVersion = '1.1.1';

/// 传输协议版本（与 PC 端 TRANSPORT_PROTOCOL_VERSION 对齐）。
const transportProtocolVersion = 1;

const audioExtensions = {
  'mp3', 'flac', 'wav', 'm4a', 'ogg',
  'wma', 'aac', 'opus', 'ape', 'wv',
};

const defaultWorkers = 4;
const largeFileThresholdBytes = 100 * 1024 * 1024;
const chunkHashSizeBytes = 128 * 1024;

// ============================================================
// 差异判定维度 id 常量（对应 spec：configurable-diff-judgment）
// 维度集合 = {diffDimensionFileSize} ∪ 用户勾选的可选维度；
// 参与语义为 AND（全部一致才判"未变"，任一不一致即"更新"）。
// ============================================================

/// 文件大小判定维度：强制参与、不可取消的基准维度（恒有值故恒参与）。
const diffDimensionFileSize = 'file_size';

/// 内容哈希判定维度：当前唯一可选判定维度（需双侧签名均含有效哈希才参与）。
const diffDimensionContentHash = 'content_hash';

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}