/// PC 签名文件导入服务。
import 'dart:io';

import '../models/signature.dart';
import 'signature_service.dart';

class ImportService {
  final SignatureService _signatureService = SignatureService();

  ImportResult lastResult = ImportResult.empty();

  Future<ImportResult> importFromFile(String filePath) async {
    try {
      final signature = await _signatureService.loadFromFile(filePath);
      lastResult = ImportResult(
        success: true,
        signature: signature,
        filePath: filePath,
      );
    } catch (e) {
      lastResult = ImportResult(
        success: false,
        error: e.toString(),
        filePath: filePath,
      );
    }
    return lastResult;
  }

  Future<ImportResult> importFromString(String jsonString) async {
    try {
      final signature = await _signatureService.loadFromString(jsonString);
      lastResult = ImportResult(
        success: true,
        signature: signature,
      );
    } catch (e) {
      lastResult = ImportResult(
        success: false,
        error: e.toString(),
      );
    }
    return lastResult;
  }
}

class ImportResult {
  final bool success;
  final Signature? signature;
  final String? error;
  final String? filePath;

  const ImportResult({
    required this.success,
    this.signature,
    this.error,
    this.filePath,
  });

  factory ImportResult.empty() => const ImportResult(success: false);
}