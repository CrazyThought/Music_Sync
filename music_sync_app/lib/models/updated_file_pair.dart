/// PC 端新文件与手机端旧文件的配对模型。
import 'file_entry.dart';

class UpdatedFilePair {
  final FileEntry pcFile;
  final FileEntry phoneFile;

  const UpdatedFilePair({
    required this.pcFile,
    required this.phoneFile,
  });

  String get relativePath => pcFile.relativePath;
}