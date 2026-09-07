/// PC 端新文件与手机端旧文件的配对模型。
import 'file_entry.dart';

class UpdatedFilePair {
  final FileEntry pcFile;
  final FileEntry phoneFile;

  /// 触发"更新"判定的差异维度 id 列表（如 file_size / content_hash）。
  /// 顺序固定为 file_size 先于 content_hash；默认空列表表示无参与维度不一致。
  final List<String> reasonDims;

  const UpdatedFilePair({
    required this.pcFile,
    required this.phoneFile,
    this.reasonDims = const [],
  });

  String get relativePath => pcFile.relativePath;
}