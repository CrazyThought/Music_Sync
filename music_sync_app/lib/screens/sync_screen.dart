/// 双向同步页 —— 拉取 PC 签名、三方合并、勾选执行、进度与结果展示。
///
/// 页面状态机：
/// `idle → preparing（拉签名 + 本地重扫）→ planned（勾选与冲突裁决）
///  → transferring（进度）→ done（结果）`。
///
/// 删除传播策略：PC 已删除 / 本机已删除的条目仅作为提示列出，默认不自动执行，
/// 需用户显式勾选「删除本机」或「从 PC 恢复」，删除动作执行前另有二次确认。
import 'package:flutter/material.dart';

import '../models/signature.dart';
import '../models/sync_plan.dart';
import '../services/config_service.dart';
import '../services/connection_service.dart';
import '../services/debug_log_service.dart';
import '../services/permission_service.dart';
import '../services/scanner_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';

/// 页面阶段。
enum _SyncStage { idle, preparing, planned, transferring, done }

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  _SyncStage _stage = _SyncStage.idle;
  String? _error;

  /// 本地重扫进度（preparing 阶段展示）。
  ScanProgress? _scanProgress;

  Signature? _pcSignature;
  Signature? _phoneSignature;
  BidirectionalSyncPlan? _plan;
  SyncService? _service;
  final Set<String> _downloadSelection = {};
  final Set<String> _uploadSelection = {};
  final Set<String> _deleteLocalSelection = {};
  final Set<String> _restoreSelection = {};
  final Map<String, ConflictResolution> _resolutions = {};

  SyncProgress? _progress;
  TransferBatchResult? _result;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    // 进入页面即自动准备一次，减少一次点击
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  // ------------------------------------------------------------------
  // 准备阶段：拉取签名 + 本地重扫 + 三方合并
  // ------------------------------------------------------------------
  Future<void> _prepare() async {
    final connection = ConnectionService.instance;
    final client = connection.syncClient;
    if (!connection.isConnected || client == null) {
      setState(() {
        _stage = _SyncStage.idle;
        _error = connection.isConnected
            ? 'PC 端未提供数据通道，请断开后重新扫码连接'
            : '尚未连接 PC，请先在主页扫码连接';
      });
      return;
    }

    final musicRoot = ConfigService.instance.config.musicFolderPath;
    if (musicRoot.isEmpty) {
      setState(() {
        _stage = _SyncStage.idle;
        _error = '请先在设置中配置本机音乐文件夹路径';
      });
      return;
    }

    final hasPermission = await PermissionService.instance.hasStoragePermission();
    if (!hasPermission) {
      final granted = await PermissionService.instance.requestStoragePermission();
      if (!granted) {
        setState(() {
          _stage = _SyncStage.idle;
          _error = '需要存储权限才能扫描与写入音乐文件';
        });
        return;
      }
    }

    setState(() {
      _stage = _SyncStage.preparing;
      _error = null;
      _scanProgress = null;
      _plan = null;
      _result = null;
      _progress = null;
    });

    try {
      final service = SyncService(client: client, localRoot: musicRoot);
      // 1) 拉取 PC 端最新签名（复用 SignatureService 的格式校验）
      final pcSignature = await service.pullRemoteSignature();
      // 2) 本地重扫，得到手机当前状态
      final phoneSignature = await ScannerService().scanDirectory(
        musicRoot,
        computeHash: ConfigService.instance.config.enableHashComputation,
        onProgress: (progress) {
          if (mounted) setState(() => _scanProgress = progress);
        },
      );
      // 3) 读取基线并做三方合并
      final baseline = await service.loadBaseline();
      final plan = service.buildPlan(
        baseline: baseline,
        pcSignature: pcSignature,
        phoneSignature: phoneSignature,
        judgmentDims: ConfigService.instance.config.diffJudgmentDims,
      );

      if (!mounted) return;
      setState(() {
        _service = service;
        _pcSignature = pcSignature;
        _phoneSignature = phoneSignature;
        _plan = plan;
        _stage = _SyncStage.planned;
        _scanProgress = null;
      });
      _selectAllByDefault();
    } catch (e) {
      DebugLogService.instance.error('同步准备失败: $e');
      if (!mounted) return;
      setState(() {
        _stage = _SyncStage.idle;
        _error = '同步准备失败: $e';
      });
    }
  }

  /// 默认勾选全部下载 / 上传项；冲突与删除提示需用户显式选择。
  void _selectAllByDefault() {
    final plan = _plan;
    if (plan == null) return;
    _downloadSelection
      ..clear()
      ..addAll(plan.downloads.map((e) => e.relativePath));
    _uploadSelection
      ..clear()
      ..addAll(plan.uploads.map((e) => e.relativePath));
    // 重新准备时清空「删除本机 / 从 PC 恢复」勾选，避免上一次的残留选择影响本次执行
    _deleteLocalSelection.clear();
    _restoreSelection.clear();
    _resolutionDefaults(plan);
  }

  /// 冲突默认裁决方式为「保留 PC 版」（用户可在界面上改）。
  void _resolutionDefaults(BidirectionalSyncPlan plan) {
    _resolutions
      ..clear()
      ..addEntries(plan.conflicts.map(
        (e) => MapEntry(e.relativePath, ConflictResolution.keepPc),
      ));
  }

  // ------------------------------------------------------------------
  // 执行阶段
  // ------------------------------------------------------------------
  Future<void> _execute() async {
    final plan = _plan;
    final service = _service;
    final pcSignature = _pcSignature;
    if (plan == null || service == null || pcSignature == null) return;

    final selection = SyncSelection(
      downloadPaths: _downloadSelection,
      uploadPaths: _uploadSelection,
      conflictResolutions: _resolutions,
      deleteLocalPaths: _deleteLocalSelection,
      restorePaths: _restoreSelection,
    );
    if (selection.isEmpty) {
      _showSnack('请至少勾选一项要同步的内容');
      return;
    }

    // 删除本机属不可撤销操作，执行前二次确认
    if (_deleteLocalSelection.isNotEmpty) {
      final confirmed = await _confirmDelete();
      if (!confirmed) return;
    }

    setState(() {
      _stage = _SyncStage.transferring;
      _cancelRequested = false;
      _progress = null;
      _result = null;
    });

    try {
      final result = await service.execute(
        plan: plan,
        selection: selection,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelRequested,
      );
      // 仅把「本次确认一致」的路径写回基线
      await service.commitBaseline(
        plan: plan,
        selection: selection,
        result: result,
        pcSignature: pcSignature,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _SyncStage.done;
        _progress = null;
      });
      DebugLogService.instance.status(
        '同步完成: 成功 ${result.successCount} / 失败 ${result.failedCount} / '
        '跳过 ${result.skippedCount} / 中止 ${result.cancelledCount}',
      );
    } catch (e) {
      DebugLogService.instance.error('同步执行失败: $e');
      if (!mounted) return;
      setState(() {
        _stage = _SyncStage.planned;
        _error = '同步执行失败: $e';
      });
    }
  }

  /// 删除本机二次确认对话框。
  Future<bool> _confirmDelete() async {
    final count = _deleteLocalSelection.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除本机文件'),
        content: Text(
          'PC 端已删除以下 $count 个文件，本机仍保留。\n'
          '继续将把这些文件从本机音乐目录中删除，此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------
  // 构建
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('双向同步'),
        actions: [
          if (_stage == _SyncStage.planned || _stage == _SyncStage.done)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新准备',
              onPressed: _prepare,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _SyncStage.idle:
        return _buildIdle();
      case _SyncStage.preparing:
        return _buildPreparing();
      case _SyncStage.planned:
        return _buildPlanView();
      case _SyncStage.transferring:
        return _buildTransferring();
      case _SyncStage.done:
        return _buildDone();
    }
  }

  /// 未准备好：展示原因与重试/返回入口。
  Widget _buildIdle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_problem, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _error ?? '尚未开始同步',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _prepare, child: const Text('重试')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回主页'),
            ),
          ],
        ),
      ),
    );
  }

  /// 准备中：展示拉签名 / 本地重扫进度。
  Widget _buildPreparing() {
    final scan = _scanProgress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('正在准备同步...'),
            const SizedBox(height: 16),
            if (scan == null || scan.phase == ScanPhase.counting)
              const LinearProgressIndicator()
            else
              LinearProgressIndicator(value: scan.progress),
            const SizedBox(height: 8),
            Text(
              scan == null
                  ? '正在拉取 PC 特征签名...'
                  : (scan.phase == ScanPhase.counting
                      ? '正在统计本机音频文件总数...'
                      : '正在扫描 ${scan.completed}/${scan.total}：${scan.currentFile}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// 计划展示：分类列表 + 勾选 + 冲突裁决 + 执行按钮。
  Widget _buildPlanView() {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();

    final rows = <Widget>[];
    if (_error != null) {
      rows.add(_banner(_error!, Colors.orange));
    }
    // 概览：六类动作数量与两端文件总数，风格与「差异详情页」的统计块一致
    rows.add(_buildPlanSummary(plan));
    if (!plan.hasChanges) {
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('两端已一致，无需同步')),
      ));
    }

    if (plan.downloads.isNotEmpty) {
      rows.add(_sectionHeader(
        icon: Icons.download,
        color: Colors.green,
        title: '下载到本机（${plan.downloads.length}）',
        trailing: _selectAllToggle(
          selected: _downloadSelection.length,
          total: plan.downloads.length,
          onChanged: (checked) => setState(() {
            _downloadSelection.clear();
            if (checked) {
              _downloadSelection.addAll(plan.downloads.map((e) => e.relativePath));
            }
          }),
        ),
      ));
      rows.addAll(plan.downloads.map((item) => _checkboxRow(
            item: item,
            checked: _downloadSelection.contains(item.relativePath),
            onChanged: (checked) => setState(() {
              _toggle(_downloadSelection, item.relativePath, checked);
            }),
          )));
    }

    if (plan.uploads.isNotEmpty) {
      rows.add(_sectionHeader(
        icon: Icons.upload,
        color: Colors.blue,
        title: '上传到 PC（${plan.uploads.length}）',
        trailing: _selectAllToggle(
          selected: _uploadSelection.length,
          total: plan.uploads.length,
          onChanged: (checked) => setState(() {
            _uploadSelection.clear();
            if (checked) {
              _uploadSelection.addAll(plan.uploads.map((e) => e.relativePath));
            }
          }),
        ),
      ));
      rows.addAll(plan.uploads.map((item) => _checkboxRow(
            item: item,
            checked: _uploadSelection.contains(item.relativePath),
            onChanged: (checked) => setState(() {
              _toggle(_uploadSelection, item.relativePath, checked);
            }),
          )));
    }

    if (plan.conflicts.isNotEmpty) {
      rows.add(_sectionHeader(
        icon: Icons.warning_amber,
        color: Colors.orange,
        title: '冲突（${plan.conflicts.length}）',
        subtitle: '两端都已修改，请逐项裁决',
      ));
      rows.addAll(plan.conflicts.map(_conflictRow));
    }

    if (plan.remoteDeleted.isNotEmpty) {
      rows.add(_sectionHeader(
        icon: Icons.delete_outline,
        color: Colors.red,
        title: 'PC 已删除（${plan.remoteDeleted.length}）',
        subtitle: '默认不自动删除，勾选后可删除本机文件',
      ));
      rows.addAll(plan.remoteDeleted.map((item) => _checkboxRow(
            item: item,
            checked: _deleteLocalSelection.contains(item.relativePath),
            onChanged: (checked) => setState(() {
              _toggle(_deleteLocalSelection, item.relativePath, checked);
            }),
            actionLabel: '删除本机',
          )));
    }

    if (plan.localDeleted.isNotEmpty) {
      rows.add(_sectionHeader(
        icon: Icons.restore,
        color: Colors.teal,
        title: '本机已删除（${plan.localDeleted.length}）',
        subtitle: 'PC 仍保留，勾选后可从 PC 恢复',
      ));
      rows.addAll(plan.localDeleted.map((item) => _checkboxRow(
            item: item,
            checked: _restoreSelection.contains(item.relativePath),
            onChanged: (checked) => setState(() {
              _toggle(_restoreSelection, item.relativePath, checked);
            }),
            actionLabel: '从 PC 恢复',
          )));
    }

    // 底部留出执行按钮的空间
    rows.add(const SizedBox(height: 96));

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(top: 4),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: FilledButton.icon(
            onPressed: _execute,
            icon: const Icon(Icons.play_arrow),
            label: Text('开始同步（已选 ${_selectedCount()} 项）'),
          ),
        ),
      ],
    );
  }

  /// 传输中：整体进度 + 当前文件 + 中止按钮。
  Widget _buildTransferring() {
    final progress = _progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(progress == null
                ? '正在开始...'
                : '正在同步 ${progress.currentIndex}/${progress.totalCount}'),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress?.overallProgress ?? 0),
            const SizedBox(height: 12),
            if (progress != null) ...[
              Text(
                '${_directionLabel(progress.direction)}：${progress.relativePath}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                progress.totalBytes > 0
                    ? '${formatSize(progress.transferredBytes)} / ${formatSize(progress.totalBytes)}'
                    : formatSize(progress.transferredBytes),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() => _cancelRequested = true);
                _showSnack('已请求中止，正在结束当前文件...');
              },
              child: const Text('中止同步'),
            ),
          ],
        ),
      ),
    );
  }

  /// 完成：结果统计与失败项重试提示。
  Widget _buildDone() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(
              result.failedCount == 0 ? Icons.check_circle : Icons.error_outline,
              color: result.failedCount == 0 ? Colors.green : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 8),
            Text(
              result.failedCount == 0 ? '同步完成' : '同步完成（有失败项）',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _statRow('成功', result.successCount, Colors.green),
        _statRow('失败', result.failedCount, Colors.red),
        _statRow('跳过', result.skippedCount, Colors.grey),
        _statRow('中止', result.cancelledCount, Colors.orange),
        const SizedBox(height: 16),
        ...result.items
            .where((e) =>
                e.status == TransferStatus.failed ||
                e.status == TransferStatus.cancelled)
            .map((e) => ListTile(
                  dense: true,
                  leading: Icon(
                    e.status == TransferStatus.failed
                        ? Icons.close
                        : Icons.pause_circle_outline,
                    color: e.status == TransferStatus.failed ? Colors.red : Colors.orange,
                  ),
                  title: Text(e.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(e.error ?? '已中止，可重新准备后续传'),
                )),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _prepare,
          child: const Text('重新准备（可续传）'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回主页'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // 小组件
  // ------------------------------------------------------------------
  /// 计划概览：六类条目数量 + 两端文件总数。
  Widget _buildPlanSummary(BidirectionalSyncPlan plan) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildStatChip('下载', plan.downloads.length, Colors.green),
              _buildStatChip('上传', plan.uploads.length, Colors.blue),
              _buildStatChip('冲突', plan.conflicts.length, Colors.orange),
              _buildStatChip('本机已删', plan.localDeleted.length, Colors.teal),
              _buildStatChip('PC 已删', plan.remoteDeleted.length, Colors.red),
              _buildStatChip('未变', plan.unchanged, Colors.grey),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'PC 端 ${_pcSignature?.scanSummary.totalFiles ?? 0} 首'
            ' · 本机 ${_phoneSignature?.scanSummary.totalFiles ?? 0} 首',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// 单个统计块：数值在上、标签在下（与差异详情页统计块风格一致）。
  Widget _buildStatChip(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  /// 分类标题行，可带右侧「全选」开关。
  Widget _sectionHeader({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// 「全选 / 全不选」切换按钮。
  Widget _selectAllToggle({
    required int selected,
    required int total,
    required ValueChanged<bool> onChanged,
  }) {
    final allSelected = total > 0 && selected == total;
    return TextButton(
      onPressed: () => onChanged(!allSelected),
      child: Text(allSelected ? '全不选' : '全选'),
    );
  }

  /// 带勾选框的文件行：标题为文件名，副标题为判定原因与两侧详情。
  Widget _checkboxRow({
    required SyncItem item,
    required bool checked,
    required ValueChanged<bool> onChanged,
    String? actionLabel,
  }) {
    return CheckboxListTile(
      dense: true,
      value: checked,
      onChanged: (value) => onChanged(value ?? false),
      title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _buildItemDetail(item, actionLabel: actionLabel),
    );
  }

  /// 条目详情：判定原因、相对路径、两侧大小与修改时间、差异原因维度、可选动作。
  ///
  /// 仅一侧存在的条目额外标注「不匹配项」，与「两端都有但已更新」明确区分。
  Widget _buildItemDetail(SyncItem item, {String? actionLabel}) {
    const detailStyle = TextStyle(fontSize: 11, color: Colors.grey);
    final lines = <Widget>[
      Text('原因：${item.reason.label}',
          style: const TextStyle(fontSize: 11, color: Colors.orange)),
      Text(item.relativePath, style: detailStyle),
    ];

    // 不匹配项：仅一侧存在时显式标注，避免与「两端都有但已更新」混淆
    if (item.existsOnPc != item.existsOnPhone) {
      lines.add(Text(
        item.existsOnPc ? '不匹配项：本机无此文件（仅 PC 端存在）' : '不匹配项：PC 端无此文件（仅本机存在）',
        style: const TextStyle(fontSize: 11, color: Colors.purple),
      ));
    }

    // 两侧条目详情，存在侧才展示
    if (item.pcFile != null) {
      lines.add(Text(
        'PC 端 ${formatSize(item.pcFile!.fileSize)} · ${_formatDate(item.pcFile!.modifiedAt)}',
        style: detailStyle,
      ));
    }
    if (item.phoneFile != null) {
      lines.add(Text(
        '本机 ${formatSize(item.phoneFile!.fileSize)} · ${_formatDate(item.phoneFile!.modifiedAt)}',
        style: detailStyle,
      ));
    }

    // 差异原因维度：仅在 content_hash 等可选维度参与且不一致时展示
    if (item.mismatchedDims.isNotEmpty) {
      lines.add(Text(
        '差异原因：${item.mismatchedDims.map(_diffDimensionLabel).join(' / ')}',
        style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
      ));
    }

    if (actionLabel != null) {
      lines.add(Text('可选动作：$actionLabel', style: detailStyle));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }

  /// 冲突行：文件信息 + 三选一裁决。
  Widget _conflictRow(SyncItem item) {
    final resolution = _resolutions[item.relativePath] ?? ConflictResolution.keepPc;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _buildItemDetail(item),
            const SizedBox(height: 8),
            SegmentedButton<ConflictResolution>(
              segments: const [
                ButtonSegment(
                  value: ConflictResolution.keepPc,
                  label: Text('保留 PC 版'),
                ),
                ButtonSegment(
                  value: ConflictResolution.keepPhone,
                  label: Text('保留手机版'),
                ),
                ButtonSegment(
                  value: ConflictResolution.keepBoth,
                  label: Text('都保留'),
                ),
              ],
              selected: {resolution},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
              onSelectionChanged: (values) => setState(() {
                _resolutions[item.relativePath] = values.first;
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部提示条。
  Widget _banner(String message, Color color) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(12),
      child: Text(message, style: TextStyle(color: color)),
    );
  }

  Widget _statRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$label: '),
          Text('$count',
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  /// 当前已勾选的动作总数（含冲突裁决）。
  int _selectedCount() {
    final plan = _plan;
    final conflictCount = plan == null
        ? 0
        : plan.conflicts
            .where((e) => _resolutions.containsKey(e.relativePath))
            .length;
    return _downloadSelection.length +
        _uploadSelection.length +
        conflictCount +
        _deleteLocalSelection.length +
        _restoreSelection.length;
  }

  void _toggle(Set<String> target, String path, bool checked) {
    if (checked) {
      target.add(path);
    } else {
      target.remove(path);
    }
  }

  /// 方向 → 中文标签。
  String _directionLabel(SyncDirection direction) {
    switch (direction) {
      case SyncDirection.download:
        return '下载';
      case SyncDirection.upload:
        return '上传';
      case SyncDirection.conflict:
        return '冲突处理';
      case SyncDirection.remoteDeleted:
        return '删除本机';
      case SyncDirection.localDeleted:
        return '从 PC 恢复';
    }
  }

  /// 将判定维度 id 映射为可读中文名；未知 id 原样返回。
  String _diffDimensionLabel(String id) {
    switch (id) {
      case diffDimensionFileSize:
        return '文件大小';
      case diffDimensionContentHash:
        return '内容哈希';
      default:
        return id;
    }
  }

  /// 毫秒时间戳 → `yyyy-MM-dd HH:mm` 文本。
  String _formatDate(int msSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
