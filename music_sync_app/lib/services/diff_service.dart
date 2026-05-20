/// 本地与 PC 签名的差异比较引擎。
import '../models/file_entry.dart';
import '../models/signature.dart';
import '../models/sync_report.dart';

class DiffService {
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
    final updated = <FileEntry>[];
    int unchanged = 0;

    for (final pcFile in pcSignature.files) {
      final phoneFile = phoneByPath[pcFile.relativePath];
      if (phoneFile == null) {
        added.add(pcFile);
      } else if (phoneFile.contentHash != pcFile.contentHash) {
        updated.add(pcFile);
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