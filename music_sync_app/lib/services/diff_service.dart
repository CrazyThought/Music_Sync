/// 本地与 PC 签名的差异比较引擎。
import '../models/file_entry.dart';
import '../models/signature.dart';
import '../models/sync_report.dart';
import '../models/updated_file_pair.dart';

class DiffService {
  /// 执行差异比较。
  ///
  /// 仅基于内容特征判定：`relativePath`（文件名/路径）+ `fileSize`（文件大小）。
  /// 不读取 `modifiedAt`、创建日期或任何音频元数据，避免文件拷贝导致
  /// 修改/创建日期变化后被误判为新增、更新或删除。
  SyncReport compare(Signature pcSignature, Signature phoneSignature) {
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
      } else if (phoneFile.fileSize != pcFile.fileSize) {
        updated.add(UpdatedFilePair(pcFile: pcFile, phoneFile: phoneFile));
      } else {
        unchanged++;
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
}