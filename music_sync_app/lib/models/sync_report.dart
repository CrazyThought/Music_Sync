/// 差异比较报告模型。
import 'file_entry.dart';
import 'updated_file_pair.dart';

class SyncReport {
  final List<FileEntry> added;
  final List<FileEntry> removed;
  final List<UpdatedFilePair> updated;
  final int unchanged;

  const SyncReport({
    required this.added,
    required this.removed,
    required this.updated,
    required this.unchanged,
  });

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty || updated.isNotEmpty;

  int get totalChanges => added.length + removed.length + updated.length;
}