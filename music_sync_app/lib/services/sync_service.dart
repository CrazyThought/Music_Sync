/// 双向同步编排服务 —— 构建计划、执行传输、维护同步基线。
///
/// 职责边界：
/// - **计划**：交由 [BidirectionalDiffService] 做三方合并，本类只做参数装配；
/// - **执行**：按「下载 / 上传 / 冲突裁决」逐项串行传输，支持断点续传与中止；
/// - **基线**：仅把「本次确认已同步一致」的路径写回基线，未完成或仅提示的路径
///   保留原基线条目，使它们下次同步仍能被正确分类（而不是被静默遗忘）。
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/file_entry.dart';
import '../models/signature.dart';
import '../models/sync_plan.dart';
import '../utils/constants.dart';
import 'bidirectional_diff_service.dart';
import 'debug_log_service.dart';
import 'grpc_sync_client.dart';
import 'hash_utils.dart';
import 'sync_baseline_service.dart';

/// 判定明细写入调试日志的条数上限：避免首次同步大库时日志文件被明细淹没。
const int _maxDecisionDetailLogs = 200;

/// 传输进度快照，供 UI 展示整体进度与当前文件。
class SyncProgress {
  /// 当前处理的文件相对路径。
  final String relativePath;

  /// 当前文件的动作方向。
  final SyncDirection direction;

  /// 当前文件已传输字节数。
  final int transferredBytes;

  /// 当前文件总字节数（未知时为 0）。
  final int totalBytes;

  /// 当前是第几项（从 1 开始）。
  final int currentIndex;

  /// 本批次总项数。
  final int totalCount;

  const SyncProgress({
    required this.relativePath,
    required this.direction,
    required this.transferredBytes,
    required this.totalBytes,
    required this.currentIndex,
    required this.totalCount,
  });

  /// 当前文件进度比例（0.0 ~ 1.0）。
  double get fileProgress =>
      totalBytes <= 0 ? 0.0 : (transferredBytes / totalBytes).clamp(0.0, 1.0);

  /// 整体进度比例（已含当前文件的小数进度）。
  double get overallProgress {
    if (totalCount <= 0) return 0.0;
    return ((currentIndex - 1) + fileProgress) / totalCount;
  }
}

/// 传输进度回调。
typedef SyncProgressCallback = void Function(SyncProgress progress);

/// 用户在同步页做出的选择。
class SyncSelection {
  /// 勾选下载的文件路径集合。
  final Set<String> downloadPaths;

  /// 勾选上传的文件路径集合。
  final Set<String> uploadPaths;

  /// 冲突路径 → 裁决方式（未裁决的冲突不会执行）。
  final Map<String, ConflictResolution> conflictResolutions;

  /// 勾选「删除本机」的路径（PC 已删除、本机仍保留）。
  final Set<String> deleteLocalPaths;

  /// 勾选「从 PC 恢复」的路径（本机已删除、PC 仍保留，等价于一次下载）。
  final Set<String> restorePaths;

  const SyncSelection({
    this.downloadPaths = const {},
    this.uploadPaths = const {},
    this.conflictResolutions = const {},
    this.deleteLocalPaths = const {},
    this.restorePaths = const {},
  });

  /// 是否没有任何需要执行的动作。
  bool get isEmpty =>
      downloadPaths.isEmpty &&
      uploadPaths.isEmpty &&
      conflictResolutions.isEmpty &&
      deleteLocalPaths.isEmpty &&
      restorePaths.isEmpty;
}

/// 内部任务描述。
class _SyncTask {
  final SyncItem item;
  final SyncDirection direction;
  final ConflictResolution? resolution;

  const _SyncTask({required this.item, required this.direction, this.resolution});
}

/// 双向同步编排服务。
class SyncService {
  /// gRPC 数据通道客户端。
  final GrpcSyncClient client;

  /// 手机端音乐根目录（下载落盘与上传取源均基于此目录）。
  final String localRoot;

  SyncService({required this.client, required this.localRoot});

  // ------------------------------------------------------------------
  // 计划
  // ------------------------------------------------------------------
  /// 拉取 PC 端最新特征签名。
  Future<Signature> pullRemoteSignature() => client.fetchSignature();

  /// 构建双向同步计划（三方合并）。
  ///
  /// 除返回计划外，本方法还会把「有动作」条目的判定依据（归类、原因、两侧大小
  /// 与哈希有效性、基线有无）写入调试日志，便于出现方向误判时直接对照证据定位。
  BidirectionalSyncPlan buildPlan({
    required Signature? baseline,
    required Signature pcSignature,
    required Signature phoneSignature,
    List<String> judgmentDims = const [],
  }) {
    final plan = BidirectionalDiffService().compare(
      baseline: baseline,
      pcSignature: pcSignature,
      phoneSignature: phoneSignature,
      judgmentDims: judgmentDims,
    );
    DebugLogService.instance.status(
      '双向差异: 下载 ${plan.downloads.length} / 上传 ${plan.uploads.length} / '
      '冲突 ${plan.conflicts.length} / PC已删 ${plan.remoteDeleted.length} / '
      '本机已删 ${plan.localDeleted.length} / 未变 ${plan.unchanged}',
    );

    // 逐条记录「有动作」条目的判定依据：出现方向误判时可直接对照证据定位原因。
    // 「未变」项不逐条记录，且明细总条数设上限，避免日志量随音乐库规模膨胀。
    final baselinePaths = <String>{
      for (final entry in baseline?.files ?? const <FileEntry>[]) entry.relativePath,
    };
    var detailCount = 0;
    for (final group in <MapEntry<String, List<SyncItem>>>[
      MapEntry('下载', plan.downloads),
      MapEntry('上传', plan.uploads),
      MapEntry('冲突', plan.conflicts),
      MapEntry('PC已删除', plan.remoteDeleted),
      MapEntry('本机已删除', plan.localDeleted),
    ]) {
      for (final item in group.value) {
        if (detailCount >= _maxDecisionDetailLogs) break;
        DebugLogService.instance.info(_formatDecisionDetail(group.key, item, baselinePaths));
        detailCount++;
      }
    }
    final remaining = plan.totalTransfers +
        plan.remoteDeleted.length +
        plan.localDeleted.length -
        detailCount;
    if (remaining > 0) {
      DebugLogService.instance.info('其余 $remaining 条判定明细已省略（仅记录前 $_maxDecisionDetailLogs 条）');
    }
    return plan;
  }

  /// 组装一条判定明细日志：相对路径、归类、原因、两侧大小与哈希有效性、基线有无。
  String _formatDecisionDetail(
    String group,
    SyncItem item,
    Set<String> baselinePaths,
  ) {
    return '同步判定[$group] ${item.relativePath}'
        ' | 原因=${item.reason.label}'
        ' | PC=${_describeEntry(item.pcFile)}'
        ' | 本机=${_describeEntry(item.phoneFile)}'
        ' | 基线=${baselinePaths.contains(item.relativePath) ? '有' : '无'}';
  }

  /// 把一个签名条目描述为「大小 / 哈希有效性(算法)」的可读片段；缺失侧返回「缺失」。
  static String _describeEntry(FileEntry? entry) {
    if (entry == null) return '缺失';
    final hashValid = entry.contentHash.isNotEmpty && entry.contentHashAlgo != 'none';
    return '${entry.fileSize}B/${hashValid ? '哈希有效' : '哈希无效'}(${entry.contentHashAlgo})';
  }

  /// 读取上次同步基线。
  Future<Signature?> loadBaseline() => SyncBaselineService.instance.load();

  // ------------------------------------------------------------------
  // 执行
  // ------------------------------------------------------------------
  /// 按用户选择执行传输，逐项串行处理并汇报进度。
  ///
  /// [isCancelled] 返回 true 时中止：当前项抛 [TransferCancelledException]，
  /// 其余项标记为 cancelled；已下载的临时文件保留以便下次续传。
  Future<TransferBatchResult> execute({
    required BidirectionalSyncPlan plan,
    required SyncSelection selection,
    SyncProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final tasks = _buildTasks(plan, selection);
    DebugLogService.instance.operation('开始同步: 共 ${tasks.length} 项');

    final results = <TransferResultItem>[];
    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      if (isCancelled?.call() ?? false) {
        results.add(TransferResultItem(
          relativePath: task.item.relativePath,
          direction: task.direction,
          status: TransferStatus.cancelled,
        ));
        continue;
      }
      results.add(await _executeTask(
        task: task,
        index: index + 1,
        count: tasks.length,
        onProgress: onProgress,
        isCancelled: isCancelled,
      ));
    }
    return TransferBatchResult(results);
  }

  /// 把「本次确认已同步一致」的路径写回基线；其余路径保留原基线条目。
  ///
  /// [plan] 本次计划，[selection] 用户选择，[result] 执行结果。
  /// [pcSignature] 本次的 PC 端签名，用于取一致路径的当前条目。
  ///
  /// 自愈语义：对 `plan.inSyncPaths`（本次判定两端内容一致）的路径回写当前
  /// PC 条目，即使历史基线残留了与两端实际都不符的脏条目，也会在本次同步后
  /// 收敛，避免同一路径在后续同步中被反复误判方向。未完成 / 仅提示 / 未裁决
  /// 的路径仍保留原基线条目，使它们下次同步仍能被正确分类。
  Future<void> commitBaseline({
    required BidirectionalSyncPlan plan,
    required SyncSelection selection,
    required TransferBatchResult result,
    required Signature pcSignature,
  }) async {
    final baselineService = SyncBaselineService.instance;
    final previous = await baselineService.load();
    // 以旧基线为底：未涉及的路径保持原状，避免丢失「上次达成一致的状态」
    final entries = <String, FileEntry>{
      for (final entry in previous?.files ?? const <FileEntry>[]) entry.relativePath: entry,
    };

    final successPaths = <String>{
      for (final item in result.items)
        if (item.status == TransferStatus.success) item.relativePath,
    };

    // 下载成功：手机已与 PC 一致，基线记录 PC 条目
    for (final item in plan.downloads) {
      final file = item.pcFile;
      if (file != null && successPaths.contains(item.relativePath)) {
        entries[item.relativePath] = file;
      }
    }

    // 上传成功：PC 已与手机一致，基线记录手机条目
    for (final item in plan.uploads) {
      final file = item.phoneFile ?? item.pcFile;
      if (file != null && successPaths.contains(item.relativePath)) {
        entries[item.relativePath] = file;
      }
    }

    // 冲突裁决成功：按裁决结果确定一致后的内容
    for (final item in plan.conflicts) {
      if (!successPaths.contains(item.relativePath)) continue;
      final resolution = selection.conflictResolutions[item.relativePath];
      if (resolution == null) continue;
      final file = resolution == ConflictResolution.keepPhone
          ? (item.phoneFile ?? item.pcFile)
          : item.pcFile;
      if (file != null) entries[item.relativePath] = file;
    }

    // 删除本机成功：两端均已不存在该文件，基线中移除对应条目
    for (final item in plan.remoteDeleted) {
      if (successPaths.contains(item.relativePath)) {
        entries.remove(item.relativePath);
      }
    }

    // 从 PC 恢复成功：本机重新持有 PC 内容，基线记录 PC 条目
    for (final item in plan.localDeleted) {
      final file = item.pcFile;
      if (file != null && successPaths.contains(item.relativePath)) {
        entries[item.relativePath] = file;
      }
    }

    // 基线自愈：本次判定为「两端内容一致」的路径，回写当前 PC 条目
    final pcByPath = <String, FileEntry>{
      for (final entry in pcSignature.files) entry.relativePath: entry,
    };
    for (final path in plan.inSyncPaths) {
      final file = pcByPath[path];
      if (file != null) {
        entries[path] = file;
      }
    }

    final files = entries.values.toList()
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final totalSize = files.fold<int>(0, (sum, e) => sum + e.fileSize);

    await baselineService.save(Signature(
      formatVersion: '2.0',
      generatedBy: 'MusicSync/App/sync-baseline',
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      scanRoot: localRoot,
      scanSummary: ScanSummary(
        totalFiles: files.length,
        totalSizeBytes: totalSize,
        scanDurationMs: 0,
      ),
      files: files,
      fingerprintAlgorithms:
          previous?.fingerprintAlgorithms ?? const {'content': 'none', 'audio': 'none'},
    ));
  }

  // ------------------------------------------------------------------
  // 内部：任务构建
  // ------------------------------------------------------------------
  /// 根据用户选择展开为可执行任务列表。
  List<_SyncTask> _buildTasks(BidirectionalSyncPlan plan, SyncSelection selection) {
    final tasks = <_SyncTask>[];
    for (final item in plan.downloads) {
      if (selection.downloadPaths.contains(item.relativePath)) {
        tasks.add(_SyncTask(item: item, direction: SyncDirection.download));
      }
    }
    for (final item in plan.uploads) {
      if (selection.uploadPaths.contains(item.relativePath)) {
        tasks.add(_SyncTask(item: item, direction: SyncDirection.upload));
      }
    }
    for (final item in plan.conflicts) {
      final resolution = selection.conflictResolutions[item.relativePath];
      if (resolution != null) {
        tasks.add(_SyncTask(
          item: item,
          direction: SyncDirection.conflict,
          resolution: resolution,
        ));
      }
    }
    // 删除提示项：仅在用户勾选对应动作时才纳入执行
    for (final item in plan.remoteDeleted) {
      if (selection.deleteLocalPaths.contains(item.relativePath)) {
        tasks.add(_SyncTask(item: item, direction: SyncDirection.remoteDeleted));
      }
    }
    for (final item in plan.localDeleted) {
      if (selection.restorePaths.contains(item.relativePath)) {
        tasks.add(_SyncTask(item: item, direction: SyncDirection.localDeleted));
      }
    }
    return tasks;
  }

  // ------------------------------------------------------------------
  // 内部：单项执行
  // ------------------------------------------------------------------
  /// 执行单个任务并归类结果（不抛出，统一转为结果项）。
  Future<TransferResultItem> _executeTask({
    required _SyncTask task,
    required int index,
    required int count,
    SyncProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final item = task.item;
    try {
      switch (task.direction) {
        case SyncDirection.download:
          return await _download(item, index, count, onProgress, isCancelled);
        case SyncDirection.upload:
          return await _upload(item, index, count, onProgress, isCancelled);
        case SyncDirection.conflict:
          return await _resolveConflict(
            task, index, count, onProgress, isCancelled);
        case SyncDirection.remoteDeleted:
          // PC 已删除、本机仍保留：按用户勾选删除本机文件
          return await _deleteLocal(item);
        case SyncDirection.localDeleted:
          // 本机已删除、PC 仍保留：按用户勾选从 PC 恢复（等价于一次下载）
          return await _download(item, index, count, onProgress, isCancelled);
      }
    } on TransferCancelledException {
      DebugLogService.instance.operation('已中止: ${item.relativePath}');
      return TransferResultItem(
        relativePath: item.relativePath,
        direction: task.direction,
        status: TransferStatus.cancelled,
      );
    } catch (e) {
      // 上传途中中止时，异常会经 gRPC 层重新包装，类型可能不再是
      // TransferCancelledException；此处以取消标志兜底，避免把用户中止误报为失败。
      if (isCancelled?.call() ?? false) {
        DebugLogService.instance.operation('已中止: ${item.relativePath}');
        return TransferResultItem(
          relativePath: item.relativePath,
          direction: task.direction,
          status: TransferStatus.cancelled,
        );
      }
      DebugLogService.instance.error('传输失败 ${item.relativePath}: $e');
      return TransferResultItem(
        relativePath: item.relativePath,
        direction: task.direction,
        status: TransferStatus.failed,
        error: e.toString(),
      );
    }
  }

  /// 下载单个文件到本机音乐目录，并按签名哈希校验。
  Future<TransferResultItem> _download(
    SyncItem item,
    int index,
    int count,
    SyncProgressCallback? onProgress,
    bool Function()? isCancelled,
  ) async {
    final bytes = await client.downloadFile(
      relativePath: item.relativePath,
      targetPath: localPathOf(item.relativePath),
      expectedContentHash: item.pcFile?.contentHash,
      onProgress: (transferred, total) => _emit(
        onProgress, item.relativePath, SyncDirection.download,
        transferred, total, index, count,
      ),
      isCancelled: isCancelled,
    );
    return TransferResultItem(
      relativePath: item.relativePath,
      direction: SyncDirection.download,
      status: TransferStatus.success,
      bytes: bytes,
    );
  }

  /// 上传单个文件到 PC 端，断点续传并按服务端重算哈希校验。
  Future<TransferResultItem> _upload(
    SyncItem item,
    int index,
    int count,
    SyncProgressCallback? onProgress,
    bool Function()? isCancelled,
  ) async {
    final path = localPathOf(item.relativePath);
    final file = File(path);
    if (!await file.exists()) {
      return TransferResultItem(
        relativePath: item.relativePath,
        direction: SyncDirection.upload,
        status: TransferStatus.skipped,
        error: '本地文件不存在',
      );
    }

    final total = await file.length();
    // 查询服务端已接收字节以续传；查询失败则整文件重传（服务端会按 offset 覆盖）
    var startOffset = 0;
    try {
      startOffset = await client.queryUploadedBytes(item.relativePath);
    } catch (e) {
      DebugLogService.instance.info('查询上传进度失败，按整文件重传: $e');
    }
    if (startOffset < 0 || (startOffset > total)) {
      startOffset = 0;
    }

    final result = await client.uploadFile(
      relativePath: item.relativePath,
      localPath: path,
      startOffset: startOffset,
      onProgress: (transferred, totalBytes) => _emit(
        onProgress, item.relativePath, SyncDirection.upload,
        transferred, totalBytes, index, count,
      ),
      isCancelled: isCancelled,
    );

    // 校验：服务端接收完成后重算的哈希应与本地一致
    final localHash = await _localHash(path, total);
    if (localHash.isNotEmpty &&
        result.contentHash.isNotEmpty &&
        localHash != result.contentHash) {
      return TransferResultItem(
        relativePath: item.relativePath,
        direction: SyncDirection.upload,
        status: TransferStatus.failed,
        error: '上传后校验不一致（本地 $localHash，服务端 ${result.contentHash}）',
        bytes: result.bytes,
      );
    }

    return TransferResultItem(
      relativePath: item.relativePath,
      direction: SyncDirection.upload,
      status: TransferStatus.success,
      bytes: result.bytes,
    );
  }

  /// 删除本机文件（用于「PC 已删除、本机仍保留」的提示项）。
  ///
  /// 同时清理可能残留的下载临时文件，避免下次被误当作续传偏移。
  Future<TransferResultItem> _deleteLocal(SyncItem item) async {
    final path = localPathOf(item.relativePath);
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      final partFile = File('$path$transferPartSuffix');
      if (await partFile.exists()) {
        await partFile.delete();
      }
      DebugLogService.instance.operation('已删除本机文件: ${item.relativePath}');
      return TransferResultItem(
        relativePath: item.relativePath,
        direction: SyncDirection.remoteDeleted,
        status: TransferStatus.success,
      );
    } on FileSystemException catch (e) {
      return TransferResultItem(
        relativePath: item.relativePath,
        direction: SyncDirection.remoteDeleted,
        status: TransferStatus.failed,
        error: '删除失败: ${e.message}',
      );
    }
  }

  /// 按裁决方式处理冲突项。
  Future<TransferResultItem> _resolveConflict(
    _SyncTask task,
    int index,
    int count,
    SyncProgressCallback? onProgress,
    bool Function()? isCancelled,
  ) async {
    final item = task.item;
    switch (task.resolution ?? ConflictResolution.keepPc) {
      case ConflictResolution.keepPc:
        // 保留 PC 版：下载覆盖手机
        return _download(item, index, count, onProgress, isCancelled);
      case ConflictResolution.keepPhone:
        // 保留手机版：上传覆盖 PC
        return _upload(item, index, count, onProgress, isCancelled);
      case ConflictResolution.keepBoth:
        // 都保留：先把手机原文件另存为「文件名 (1).ext」，再下载 PC 版覆盖规范路径。
        // 副本仅存在于手机，会在下次同步时作为「上传」项出现，用户可再决定是否上传。
        await _backupLocalCopy(item.relativePath, onProgress, index, count);
        return _download(item, index, count, onProgress, isCancelled);
    }
  }

  /// 把本机文件另存为「文件名 (n).ext」副本，返回副本相对路径。
  Future<String> _backupLocalCopy(
    String relativePath,
    SyncProgressCallback? onProgress,
    int index,
    int count,
  ) async {
    final source = File(localPathOf(relativePath));
    if (!await source.exists()) return relativePath;

    final backupRelative = _nextAvailableName(relativePath);
    final backup = File(localPathOf(backupRelative));
    await backup.parent.create(recursive: true);
    await source.copy(backup.path);
    DebugLogService.instance.operation('冲突保留副本: $relativePath → $backupRelative');
    final size = await backup.length();
    _emit(onProgress, relativePath, SyncDirection.conflict, size, size, index, count);
    return backupRelative;
  }

  /// 生成不与现有文件冲突的「文件名 (n).ext」相对路径。
  String _nextAvailableName(String relativePath) {
    final dir = p.dirname(relativePath);
    final base = p.basenameWithoutExtension(relativePath);
    final ext = p.extension(relativePath);
    for (var n = 1; n < 1000; n++) {
      final candidate = dir == '.' ? '$base ($n)$ext' : '$dir/$base ($n)$ext';
      if (!File(localPathOf(candidate)).existsSync()) {
        return candidate;
      }
    }
    // 极端情况下回退时间戳后缀，保证一定不冲突
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return dir == '.' ? '$base ($stamp)$ext' : '$dir/$base ($stamp)$ext';
  }

  /// 本机绝对路径：相对路径统一以 `/` 分隔，逐段拼接以兼容各平台分隔符。
  String localPathOf(String relativePath) =>
      p.joinAll([localRoot, ...relativePath.split('/')]);

  /// 按与扫描器一致的策略计算本机文件哈希。
  Future<String> _localHash(String path, int fileSize) {
    if (fileSize >= largeFileThresholdBytes) {
      return computeChunkedHash(path, fileSize);
    }
    return computeXxh64(path);
  }

  /// 统一上报进度。
  void _emit(
    SyncProgressCallback? callback,
    String relativePath,
    SyncDirection direction,
    int transferred,
    int total,
    int index,
    int count,
  ) {
    callback?.call(SyncProgress(
      relativePath: relativePath,
      direction: direction,
      transferredBytes: transferred,
      totalBytes: total,
      currentIndex: index,
      totalCount: count,
    ));
  }
}
