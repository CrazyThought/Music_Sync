/// 双向同步计划与传输结果的模型定义。
///
/// 与 PC 端 gRPC 契约（`proto/musicsync.proto`）配合，描述「三方合并」得到的
/// 方向化差异，以及执行传输后的逐文件结果。
import 'file_entry.dart';

/// 单个文件的同步动作方向（由三方合并推导）。
enum SyncDirection {
  /// PC → 手机：PC 新增，或 PC 变更而手机未变。
  download,

  /// 手机 → PC：手机新增，或手机变更而 PC 未变。
  upload,

  /// 两端均已变更且内容不同，需用户裁决。
  conflict,

  /// PC 已删除、手机仍保留 —— 仅提示，不自动删除。
  remoteDeleted,

  /// 手机已删除、PC 仍保留 —— 仅提示，不自动删除。
  localDeleted,
}

/// 条目被归入某方向的原因，用于同步页展示与调试日志记录。
enum SyncReason {
  /// PC 新增（本机无此文件）。
  pcAdded,
  /// PC 已更新（本机未变）。
  pcUpdated,
  /// 本机新增（PC 无此文件）。
  phoneAdded,
  /// 本机已更新（PC 未变）。
  phoneUpdated,
  /// 两端均已修改且内容不同。
  bothChanged,
  /// 两端各自新增同名文件且内容不同。
  bothAdded,
  /// PC 已删除、本机仍保留。
  pcDeleted,
  /// 本机已删除、PC 仍保留。
  phoneDeleted,
}

/// 原因 → 中文文案映射，供同步页与日志直接展示。
extension SyncReasonLabel on SyncReason {
  String get label {
    switch (this) {
      case SyncReason.pcAdded: return 'PC 新增（本机无此文件）';
      case SyncReason.pcUpdated: return 'PC 已更新（本机未变）';
      case SyncReason.phoneAdded: return '本机新增（PC 无此文件）';
      case SyncReason.phoneUpdated: return '本机已更新（PC 未变）';
      case SyncReason.bothChanged: return '两端均已修改，内容不同';
      case SyncReason.bothAdded: return '两端各自新增同名文件，内容不同';
      case SyncReason.pcDeleted: return 'PC 已删除（本机仍保留）';
      case SyncReason.phoneDeleted: return '本机已删除（PC 仍保留）';
    }
  }
}

/// 计划中的单个文件条目（可携带两侧签名条目，缺失侧为 null）。
///
/// 每个条目都携带 [reason]，说明其被归入当前方向的原因，供 UI 展示与日志追踪。
class SyncItem {
  /// 相对于各自扫描根目录的文件路径（统一 `/` 分隔）。
  final String relativePath;

  /// PC 侧签名条目；PC 端已删除时为 null。
  final FileEntry? pcFile;

  /// 手机侧签名条目；手机端已删除时为 null。
  final FileEntry? phoneFile;

  /// 归类原因，用于 UI 展示与日志。
  final SyncReason reason;

  /// 触发「两端内容不一致」判定的维度 id 列表，顺序固定为 file_size 先于 content_hash。
  /// 仅两侧条目均存在时才有值；仅一侧存在或无需动作的条目为空列表。
  final List<String> mismatchedDims;

  const SyncItem({
    required this.relativePath,
    this.pcFile,
    this.phoneFile,
    required this.reason,
    this.mismatchedDims = const [],
  });

  /// PC 侧是否存在该文件。
  bool get existsOnPc => pcFile != null;

  /// 本机侧是否存在该文件。
  bool get existsOnPhone => phoneFile != null;

  /// PC 侧文件大小；PC 侧不存在时为 null。
  int? get pcSize => pcFile?.fileSize;

  /// 本机侧文件大小；本机侧不存在时为 null。
  int? get phoneSize => phoneFile?.fileSize;

  /// 用于展示与预估的字节大小：优先取本次传输来源侧的大小。
  int get sizeBytes => pcFile?.fileSize ?? phoneFile?.fileSize ?? 0;

  /// 文件名（路径最后一段），用于列表与进度展示。
  String get fileName => relativePath.split('/').last;
}

/// 冲突裁决方式。
enum ConflictResolution {
  /// 保留 PC 版：下载 PC 文件覆盖手机。
  keepPc,

  /// 保留手机版：上传手机文件覆盖 PC。
  keepPhone,

  /// 都保留：PC 版另存为「文件名 (1).扩展名」，两侧各留一份。
  keepBoth,
}

/// 三方合并得到的双向同步计划。
class BidirectionalSyncPlan {
  /// 可下载项（PC → 手机）。
  final List<SyncItem> downloads;

  /// 可上传项（手机 → PC）。
  final List<SyncItem> uploads;

  /// 冲突项，需用户裁决。
  final List<SyncItem> conflicts;

  /// PC 已删除、手机仍保留的提示项。
  final List<SyncItem> remoteDeleted;

  /// 手机已删除、PC 仍保留的提示项。
  final List<SyncItem> localDeleted;

  /// 本次判定为「两端内容一致」的路径集合，用于基线自愈。
  final Set<String> inSyncPaths;

  const BidirectionalSyncPlan({
    required this.downloads,
    required this.uploads,
    required this.conflicts,
    required this.remoteDeleted,
    required this.localDeleted,
    required this.inSyncPaths,
  });

  /// 是否存在需要用户处理的变化（含仅提示项）。
  bool get hasChanges =>
      downloads.isNotEmpty ||
      uploads.isNotEmpty ||
      conflicts.isNotEmpty ||
      remoteDeleted.isNotEmpty ||
      localDeleted.isNotEmpty;

  /// 两端内容一致、无需处理的文件数。
  int get unchanged => inSyncPaths.length;

  /// 需要执行传输的动作总数（不含仅提示项）。
  int get totalTransfers => downloads.length + uploads.length + conflicts.length;
}

/// 单文件传输结果状态。
enum TransferStatus {
  /// 传输并校验通过。
  success,

  /// 传输失败（网络异常 / 校验不一致）。
  failed,

  /// 跳过（用户取消勾选、目标已一致等）。
  skipped,

  /// 用户中止。
  cancelled,
}

/// 单文件传输结果。
class TransferResultItem {
  /// 文件相对路径。
  final String relativePath;

  /// 本次动作方向。
  final SyncDirection direction;

  /// 结果状态。
  final TransferStatus status;

  /// 失败原因（status 为 failed 时有效）。
  final String? error;

  /// 实际传输字节数。
  final int bytes;

  const TransferResultItem({
    required this.relativePath,
    required this.direction,
    required this.status,
    this.error,
    this.bytes = 0,
  });

  /// 文件名（路径最后一段）。
  String get fileName => relativePath.split('/').last;
}

/// 一个同步批次的汇总结果。
class TransferBatchResult {
  /// 逐文件结果，顺序与执行顺序一致。
  final List<TransferResultItem> items;

  const TransferBatchResult(this.items);

  /// 成功数。
  int get successCount =>
      items.where((e) => e.status == TransferStatus.success).length;

  /// 失败数。
  int get failedCount =>
      items.where((e) => e.status == TransferStatus.failed).length;

  /// 跳过数。
  int get skippedCount =>
      items.where((e) => e.status == TransferStatus.skipped).length;

  /// 中止数。
  int get cancelledCount =>
      items.where((e) => e.status == TransferStatus.cancelled).length;

  /// 是否全部成功。
  bool get allSucceeded => items.isNotEmpty && successCount == items.length;
}
