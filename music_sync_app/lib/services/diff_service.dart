/// 本地与 PC 签名的差异比较引擎。
import '../models/file_entry.dart';
import '../models/signature.dart';
import '../models/sync_report.dart';
import '../models/updated_file_pair.dart';
import '../utils/constants.dart';

class DiffService {
  /// 执行差异比较。
  ///
  /// 路径匹配的文件对按「参与判定维度集合」做 AND 合并判定：
  /// - `file_size` 恒参与（恒有值，不可取消的基准维度）；
  /// - 可选维度（如 `content_hash`）仅当两侧签名该值均有效才参与；
  /// - 全部参与维度相等判"未变"，任一参与维度不一致即判"更新"；
  /// - 单侧缺值的维度自动放行不参与，避免一端未算哈希导致误报。
  ///
  /// [pcSignature] PC 端最新的特征文件数据。
  /// [phoneSignature] 手机端当前的特征文件数据。
  /// [judgmentDims] 用户额外启用的可选判定维度 id 列表（不含强制维度 file_size）。
  SyncReport compare(
    Signature pcSignature,
    Signature phoneSignature, {
    List<String> judgmentDims = const [],
  }) {
    final pcByPath = <String, FileEntry>{};
    for (final f in pcSignature.files) {
      pcByPath[f.relativePath] = f;
    }

    final phoneByPath = <String, FileEntry>{};
    for (final f in phoneSignature.files) {
      phoneByPath[f.relativePath] = f;
    }

    final added = <FileEntry>[];
    final updated = <UpdatedFilePair>[];
    int unchanged = 0;

    for (final pcFile in pcSignature.files) {
      final phoneFile = phoneByPath[pcFile.relativePath];
      if (phoneFile == null) {
        added.add(pcFile);
        continue;
      }
      // 收集「参与判定且两侧不一致」的维度，顺序固定为 file_size 先于 content_hash。
      final mismatchedDims = <String>[];
      if (pcFile.fileSize != phoneFile.fileSize) {
        mismatchedDims.add(diffDimensionFileSize);
      }
      // content_hash 维度：需用户启用且双侧签名均含有效哈希（非空、算法非 none）才参与。
      if (judgmentDims.contains(diffDimensionContentHash) &&
          _isContentHashValid(pcFile) &&
          _isContentHashValid(phoneFile) &&
          pcFile.contentHash != phoneFile.contentHash) {
        mismatchedDims.add(diffDimensionContentHash);
      }
      if (mismatchedDims.isEmpty) {
        unchanged++;
      } else {
        updated.add(UpdatedFilePair(
          pcFile: pcFile,
          phoneFile: phoneFile,
          reasonDims: mismatchedDims,
        ));
      }
    }

    final removed = <FileEntry>[];
    for (final phoneFile in phoneSignature.files) {
      if (!pcByPath.containsKey(phoneFile.relativePath)) {
        removed.add(phoneFile);
      }
    }

    return SyncReport(
      added: added,
      removed: removed,
      updated: updated,
      unchanged: unchanged,
    );
  }

  /// 判断单侧签名中 content_hash 维度是否具备有效值。
  ///
  /// 有效条件：哈希串非空且算法标识非 'none'（'none' 表示该侧未计算哈希）。
  static bool _isContentHashValid(FileEntry entry) =>
      entry.contentHash.isNotEmpty && entry.contentHashAlgo != 'none';
}