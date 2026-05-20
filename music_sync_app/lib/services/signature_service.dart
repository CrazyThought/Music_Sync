/// 特征文件读写服务。
import 'dart:convert';
import 'dart:io';

import '../models/signature.dart';

class SignatureService {
  static const formatVersion = '2.0';

  Future<Signature> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('特征文件不存在', filePath);
    }
    final content = await file.readAsString(encoding: utf8);
    final json = jsonDecode(content) as Map<String, dynamic>;
    return _validate(Signature.fromJson(json));
  }

  Future<Signature> loadFromString(String jsonString) async {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return _validate(Signature.fromJson(json));
  }

  Future<void> saveToFile(Signature signature, String filePath) async {
    final file = File(filePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final jsonStr = const JsonEncoder.withIndent('  ').convert(signature.toJson());
    await file.writeAsString(jsonStr, encoding: utf8, flush: true);
  }

  Signature _validate(Signature signature) {
    if (signature.formatVersion != formatVersion) {
      throw FormatException('不支持的特征文件版本: ${signature.formatVersion}');
    }
    final algo = signature.fingerprintAlgorithms['content'];
    if (algo != null && algo != 'xxh64') {
      throw FormatException('不支持的哈希算法: $algo');
    }
    return signature;
  }
}