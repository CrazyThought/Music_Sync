/// 双向同步的三方合并差异引擎。
///
/// 以「上次同步基线（B）」为参照，比较 PC 当前签名（P）与手机当前签名（M），
/// 推导每个文件应执行的方向化动作：
/// - 下载：P 新增，或 P 变更而 M 未变；
/// - 上传：M 新增，或 M 变更而 P 未变；
/// - 冲突：两端均变更且内容不同（含双方各自新增同名文件且内容不同）；
/// - 仅提示：一端已删除而另一端仍保留（不自动传播删除）。
///
/// 判定维度与单向 [DiffService] 保持一致：`file_size` 恒参与，可选维度需
/// 用户启用且双侧签名均含有效值才参与，启用维度之间取 AND。
import '../models/file_entry.dart';
import '../models/signature.dart';
import '../models/sync_plan.dart';
import '../utils/constants.dart';

/// 三方合并差异引擎。
class BidirectionalDiffService {
  /// 执行三方合并，返回方向化同步计划。
  ///
  /// 判定顺序：
  /// ① 两侧均存在时，先直接比较两端内容 —— 内容一致即判「未变」并计入 `inSyncPaths`，
  ///    与基线是否陈旧、是否单侧缺哈希无关；
  /// ② 两侧内容不一致时，才借助基线区分「下载 / 上传 / 冲突」；
  /// ③ 仅一侧存在时，按基线有无区分「新增（需传输）」与「已删除（仅提示）」。
  ///
  /// [baseline] 上次同步成功后的签名快照；为空表示首次同步（无历史），
  /// 此时两端同时存在且内容不同的文件一律按「双方各自新增」处理。
  /// [pcSignature] PC 端当前签名。
  /// [phoneSignature] 手机端当前签名。
  /// [judgmentDims] 用户额外启用的可选判定维度 id 列表（不含强制维度）。
  BidirectionalSyncPlan compare({
    required Signature? baseline,
    required Signature pcSignature,
    required Signature phoneSignature,
    List<String> judgmentDims = const [],
  }) {
    final baseByPath = _indexByPath(baseline);
    final pcByPath = _indexByPath(pcSignature);
    final phoneByPath = _indexByPath(phoneSignature);

    // 取三方路径的并集并按路径排序，保证结果稳定可复现
    final allPaths = <String>{
      ...baseByPath.keys,
      ...pcByPath.keys,
      ...phoneByPath.keys,
    }.toList()
      ..sort();

    final downloads = <SyncItem>[];
    final uploads = <SyncItem>[];
    final conflicts = <SyncItem>[];
    final remoteDeleted = <SyncItem>[];
    final localDeleted = <SyncItem>[];
    final inSyncPaths = <String>{};

    for (final path in allPaths) {
      final base = baseByPath[path];
      final pc = pcByPath[path];
      final phone = phoneByPath[path];

      // 两端都不存在：无动作（可能为基线残留）
      if (pc == null && phone == null) continue;

      // 仅本机存在：基线无 → 本机新增（可上传）；基线有 → PC 已删除（仅提示）
      if (pc == null) {
        final isNewOnPhone = base == null;
        final item = SyncItem(
          relativePath: path,
          phoneFile: phone,
          reason: isNewOnPhone ? SyncReason.phoneAdded : SyncReason.pcDeleted,
        );
        if (isNewOnPhone) {
          uploads.add(item);
        } else {
          remoteDeleted.add(item);
        }
        continue;
      }

      // 仅 PC 存在：基线无 → PC 新增（可下载）；基线有 → 本机已删除（仅提示）
      if (phone == null) {
        final isNewOnPc = base == null;
        final item = SyncItem(
          relativePath: path,
          pcFile: pc,
          reason: isNewOnPc ? SyncReason.pcAdded : SyncReason.phoneDeleted,
        );
        if (isNewOnPc) {
          downloads.add(item);
        } else {
          localDeleted.add(item);
        }
        continue;
      }

      // 两侧均存在：先直接比较两端内容 —— 内容一致即判「未变」。
      // 这是方向判定的不变量：内容一致的文件绝不能出现在下载/上传中，
      // 与基线是否陈旧、是否单侧缺哈希、content_hash_algo 是否一致均无关。
      if (_isSameContent(pc, phone, judgmentDims)) {
        inSyncPaths.add(path);
        continue;
      }

      // 两端内容不一致，再借助基线判断「谁改了」
      if (base == null) {
        // 首次同步（无基线）：两端各自持有不同内容，无法判断谁该覆盖谁
        conflicts.add(SyncItem(
          relativePath: path,
          pcFile: pc,
          phoneFile: phone,
          reason: SyncReason.bothAdded,
          mismatchedDims: _mismatchDims(pc, phone, judgmentDims),
        ));
        continue;
      }

      final pcChanged = !_isSameContent(base, pc, judgmentDims);
      final phoneChanged = !_isSameContent(base, phone, judgmentDims);

      if (pcChanged && !phoneChanged) {
        downloads.add(SyncItem(
          relativePath: path,
          pcFile: pc,
          phoneFile: phone,
          reason: SyncReason.pcUpdated,
          mismatchedDims: _mismatchDims(pc, phone, judgmentDims),
        ));
      } else if (!pcChanged && phoneChanged) {
        uploads.add(SyncItem(
          relativePath: path,
          pcFile: pc,
          phoneFile: phone,
          reason: SyncReason.phoneUpdated,
          mismatchedDims: _mismatchDims(pc, phone, judgmentDims),
        ));
      } else {
        // 两端相对基线均未变（基线记录了第三种状态）或两端均已变更 → 需人工裁决
        conflicts.add(SyncItem(
          relativePath: path,
          pcFile: pc,
          phoneFile: phone,
          reason: SyncReason.bothChanged,
          mismatchedDims: _mismatchDims(pc, phone, judgmentDims),
        ));
      }
    }

    return BidirectionalSyncPlan(
      downloads: downloads,
      uploads: uploads,
      conflicts: conflicts,
      remoteDeleted: remoteDeleted,
      localDeleted: localDeleted,
      inSyncPaths: inSyncPaths,
    );
  }

  /// 按路径建立索引；签名为空时返回空索引。
  Map<String, FileEntry> _indexByPath(Signature? signature) {
    final result = <String, FileEntry>{};
    if (signature == null) return result;
    for (final entry in signature.files) {
      result[entry.relativePath] = entry;
    }
    return result;
  }

  /// 判断两个条目内容是否一致（按参与判定维度取 AND）。
  ///
  /// `file_size` 恒参与；`content_hash` 仅在启用且两侧哈希均有效时参与，
  /// 单侧缺值时自动放行，避免一端未算哈希导致误判。
  bool _isSameContent(FileEntry a, FileEntry b, List<String> judgmentDims) {
    if (a.fileSize != b.fileSize) return false;
    if (judgmentDims.contains(diffDimensionContentHash) &&
        _isContentHashValid(a) &&
        _isContentHashValid(b) &&
        a.contentHash != b.contentHash) {
      return false;
    }
    return true;
  }

  /// 收集「参与判定且两侧不一致」的维度 id，顺序固定为 file_size 先于 content_hash。
  ///
  /// 语义与单向 DiffService 保持一致：file_size 恒参与；content_hash 仅在启用且
  /// 两侧哈希均有效时才参与。仅一侧存在时由调用方传空列表。
  List<String> _mismatchDims(FileEntry a, FileEntry b, List<String> judgmentDims) {
    final dims = <String>[];
    if (a.fileSize != b.fileSize) {
      dims.add(diffDimensionFileSize);
    }
    if (judgmentDims.contains(diffDimensionContentHash) &&
        _isContentHashValid(a) &&
        _isContentHashValid(b) &&
        a.contentHash != b.contentHash) {
      dims.add(diffDimensionContentHash);
    }
    return dims;
  }

  /// 判断单侧签名中 content_hash 维度是否具备有效值。
  static bool _isContentHashValid(FileEntry entry) =>
      entry.contentHash.isNotEmpty && entry.contentHashAlgo != 'none';
}
