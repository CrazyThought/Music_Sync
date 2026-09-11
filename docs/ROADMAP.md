# MusicSync 开发路线图 & 代办事项

## 阶段零：项目初始化（当前阶段）

### 0.1 项目骨架搭建
- [x] 0.1.1 创建项目根目录结构
- [x] 0.1.2 编写架构设计文档 (`docs/ARCHITECTURE.md`)
- [x] 0.1.3 编写特征文件规范 (`docs/SIGNATURE_SPEC.md`)
- [x] 0.1.4 编写开发 SOP (`SOP.md`)
- [x] 0.1.5 初始化 PC 端 Python 项目 (`music_sync_pc/`)
- [x] 0.1.6 初始化手机端 Flutter 项目 (`music_sync_app/`)

### 0.2 PC 端核心服务层
- [x] 0.2.1 实现 `core/config.py` — 配置管理器（加载/保存/降级）
- [x] 0.2.2 实现 `core/logger.py` — 日志管理器（文件轮转、分级）
- [x] 0.2.3 实现 `utils/constants.py` — 常量定义（扩展名、哈希策略）
- [x] 0.2.4 实现 `utils/file_utils.py` — 文件工具函数
- [x] 0.2.5 实现 `services/hash_utils.py` — xxHash 计算 & 大文件分块
- [x] 0.2.6 实现 `services/audio_meta.py` — ID3 标签提取（mutagen）
- [x] 0.2.7 实现 `services/scanner.py` — 文件夹扫描引擎
- [x] 0.2.8 实现 `services/signature.py` — 特征文件生成与校验
- [x] 0.2.9 实现 `services/diff_service.py` — PC 端差异自检
- [x] 0.2.10 实现 `services/sync_transport.py` — 预留扩展接口（ABC + NoopTransport）

### 0.3 PC 端 GUI 界面
- [x] 0.3.1 实现 `main.py` — 程序入口 & 单实例检查
- [x] 0.3.2 实现 `app.py` — 主窗口容器 & 标签页框架
- [x] 0.3.3 实现 `pages/scan_page.py` — 扫描页（路径选择 + 扫描触发）
- [x] 0.3.4 实现 `pages/result_page.py` — 结果页（分类表格 + 导出）
- [x] 0.3.5 实现 `pages/settings_page.py` — 设置页（扫描参数 + 外观）
- [x] 0.3.6 实现状态栏 & 实时进度反馈

### 0.4 PC 端集成验证
- [x] 0.4.1 端到端测试：选文件夹 → 扫描 → 显示结果 → 导出 JSON
- [x] 0.4.2 增量扫描测试：添加/删除/修改文件后重扫，验证差异正确
- [~] 0.4.3 异常测试：空文件夹（已通过）、损坏文件、无权限目录（需 GUI 环境）
- [~] 0.4.4 配置降级测试：损坏 config.json 降级正常（已通过）、删除 config.json 后程序正常启动（需 GUI 环境）
- [~] 0.4.5 PyInstaller 打包验证：构建已通过（`python -m PyInstaller build.spec --clean --noconfirm` 成功产出 exe，并已确认归档内含 `grpc`/`cygrpc`/`google.protobuf`/`generated.musicsync_pb2`）；**exe 在纯净 Windows 上的实际运行验证仍待补**

### 0.5 手机端 Flutter 搭建
- [x] 0.5.1 初始化 Flutter 项目 & 安装依赖（pubspec.yaml 配置完成）
- [x] 0.5.2 实现数据模型层（Signature、FileEntry、SyncReport、AppConfig）
- [x] 0.5.3 实现 `config_service.dart` — Hive 配置读写
- [x] 0.5.4 实现 `scanner_service.dart` — 手机端文件夹扫描
- [x] 0.5.5 实现 `signature_service.dart` — 特征文件生成
- [x] 0.5.6 实现 `diff_service.dart` — 差异比较引擎
- [x] 0.5.7 实现 `import_service.dart` — PC 签名导入
- [x] 0.5.8 实现主页 `home_screen.dart` — 状态概览卡片
- [x] 0.5.9 实现扫描页 `scan_screen.dart`
- [x] 0.5.10 实现导入页 `import_screen.dart`
- [x] 0.5.11 实现差异页 `diff_screen.dart` — 分类展示变更
- [x] 0.5.12 实现设置页 `settings_screen.dart`
- [ ] 0.5.13 端到端验证：扫描手机 → 导入 PC 签名 → 查看差异（需 Flutter 运行环境）

---

## 阶段一：测试覆盖（当前阶段）

### 1.1 PC 端单元测试
- [x] 1.1.1 `test_hash_utils.py` — xxHash 正确性 & 分块策略
- [x] 1.1.2 `test_audio_meta.py` — 正常标签 & 损坏标签 & 无标签
- [x] 1.1.3 `test_scanner.py` — 全量扫描 & 增量扫描 & 过滤
- [x] 1.1.4 `test_signature.py` — 生成 & 校验 & 版本兼容
- [x] 1.1.5 `test_diff_service.py` — 新增/删除/更新/移动/未变
- [x] 1.1.6 `test_config.py` — 加载 & 保存 & 降级

### 1.2 手机端单元测试
- [ ] 1.2.1 `diff_service_test.dart` — 各种比较场景
- [ ] 1.2.2 `signature_service_test.dart` — 序列化 & 反序列化
- [ ] 1.2.3 `config_service_test.dart` — Hive 读写

---

## 阶段二：增强与优化（后续阶段）

### 2.1 高级匹配
- [ ] 2.1.1 集成 Chromaprint 音频指纹（PC 端）
- [ ] 2.1.2 实现基于音频指纹的跨音质匹配
- [ ] 2.1.3 实现文件移动/重命名检测（content_hash 匹配 + 路径变化）

### 2.2 局域网传输（预留功能激活）
- [x] 2.2.1 重构 `SyncTransport` 传输通道接口为中立能力语义（`start`/`stop`/`get_device_info`/`create_pairing`），解耦发现与传输层。见 `.trae/specs/refactor-transport-and-qr-pairing`
- [x] 2.2.2 实现局域网二维码配对连接（建连 + 握手 + 两端连接状态展示）：PC 端 `QrPairingTransport`（单会话 HTTP 服务 + 一次性 token + 二维码渲染，POST 握手回传对端信息），连接入口内嵌扫描页卡片（`PairingCard` + 二维码弹窗）；手机端 `QrPairingService` + 扫码页 + 全局 `ConnectionService` 驱动主页连接状态卡片。见 `.trae/specs/refactor-transport-and-qr-pairing` 与 `.trae/documents/pc-connection-card-and-tab-width-fix`
- [x] 2.2.3 实现连接保活检测（心跳轮询）：手机端每 3 秒发送 `POST /heartbeat`（携带 peer_id），PC 端校验并轮询对端存活，任一端连续 9 秒无信号即自动断开并复位连接状态。见 `.trae/documents/lan-connection-liveness-heartbeat.md`
- [x] 2.2.4 实现手机端 `fetchRemoteSignature()` — 握手后通过 gRPC `GetSignature` 从 PC 拉取特征签名（以 SIGNATURE_SPEC v2.0 的 JSON 字节承载，复用 `SignatureService` 校验）。见 `.trae/specs/grpc-bidirectional-file-sync`
- [x] 2.2.5 实现文件断点续传下载与上传 — 下载以本地 `.musicsync-part` 长度作续传偏移，上传以 `GetUploadStatus` 查询服务端已接收字节；两端均在临时文件上续写，完成后校验哈希再原子落盘
- [x] 2.2.6 实现 gRPC 数据面鉴权与路径越权防护 — 所有 RPC 校验 `peer-id` metadata（未配对/非法返回 `UNAUTHENTICATED`），`relative_path` 规范化后必须位于音乐根目录内
- [ ] 2.2.7 实现连接密码验证 & 设备白名单

### 2.5 gRPC 双向文件同步（完整闭环）
- [x] 2.5.1 定义 proto 契约并打通两端代码生成 — `proto/musicsync.proto` + `scripts/generate_proto.ps1`（Python stub 至 `music_sync_pc/generated/`，Dart stub 至 `music_sync_app/lib/generated/`）
- [x] 2.5.2 PC 端 gRPC 服务 `services/grpc_transport.py` — 签名下发、文件下发/接收（分块流式 + 断点续传）、上传进度查询、鉴权拦截器、路径越权防护、传输进度快照；与配对会话同生命周期启停
- [x] 2.5.3 手机端 gRPC 客户端 `lib/services/grpc_sync_client.dart` — 建连/断连、签名拉取、下载（续传 + 哈希校验）、上传（续传 + 服务端哈希回验）、上传进度查询；由 `ConnectionService` 持有生命周期
- [x] 2.5.4 会话桥接 — HTTP `/pair` 握手响应附带 `grpc_port`，手机端据此建立数据面通道；`peer-id` 作为唯一桥接标识
- [x] 2.5.5 双向三方合并差异 `lib/services/bidirectional_diff_service.dart` — 以基线 B / PC 当前 P / 手机当前 M 分类为 下载 / 上传 / 冲突 / PC已删 / 本机已删 / 未变
- [x] 2.5.6 同步基线持久化 `lib/services/sync_baseline_service.dart` — 仅把「本次确认一致」的路径写回基线，未完成与仅提示项保留原基线条目以便下次正确分类
- [x] 2.5.7 同步编排与冲突解决 `lib/services/sync_service.dart` — 逐项串行执行、进度上报、中止（保留临时文件可续传）；冲突支持「保留 PC 版 / 保留手机版 / 都保留」
- [x] 2.5.8 双向同步页 `lib/screens/sync_screen.dart` — 准备（拉签名 + 本地重扫）→ 勾选与冲突裁决 → 传输进度（含中止）→ 结果报告（含失败项重试）
- [x] 2.5.9 删除传播策略 — 删除仅提示不自动执行，需用户显式勾选「删除本机」或「从 PC 恢复」，删除前二次确认
- [x] 2.5.10 PC 端传输进度展示 — 连接卡片轮询 `GrpcSyncServer.progress` 展示「当前传输文件 + 百分比」
- [x] 2.5.11 修复同步方向误判 —— 引入方向判定不变量「两侧内容一致即判未变」，不再以基线单侧条目直接决定方向；并新增基线自愈（本次一致路径回写当前 PC 条目），消除历史脏基线导致的反复误判。见 `.trae/specs/fix-sync-direction-and-enrich-sync-page`
- [x] 2.5.12 同步页信息增强 —— 顶部六类统计概览（下载/上传/冲突/本机已删/PC已删/未变）与两端文件总数；条目展示判定原因、两侧大小与修改时间、差异原因维度；**仅一侧存在的不匹配项显式标注「对方无此文件」**
- [x] 2.5.13 配套修复 —— 判定依据逐条写入调试日志（含路径/原因/两侧大小/哈希有效性/基线是否存在，明细上限 200 条）；重新准备时重置全部勾选状态；手机端哈希计算失败时 `content_hash_algo` 归一为 `none`（保证「空哈希配 none」的签名约定）
- [x] 2.5.14 修复「PC 端签名需先导出才能参与同步」的衔接缺陷 —— 原先「开始扫描」只更新内存、不落盘，数据面 `GetSignature` 读的 `output_folder/pc_signature.json` 只由「导出签名文件」按钮写入，导致同步可能下发过期签名的 `file_size`/路径，把两端其实一致的文件误判为「需上传/需下载」。现改为**扫描完成后自动落盘签名**（落盘失败不影响扫描，状态栏给出提示，「导出签名文件」按钮保留为手动重写入口）。见 `.trae/specs/auto-persist-pc-signature`

### 2.3 移动端增强
- [x] 2.3.1 实现扫描进度条：先获取文件总数，按当前进度实时展示扫描进度，并在进度条上显示当前正在扫描的文件名
- [x] 2.3.2 实现调试日志显示：设置界面添加开关，开启后在设置按钮旁显示日志按钮，点击弹出日志弹窗（含状态、操作、报错等处理后便于理解与问题定位的详细信息）
- [ ] 2.3.3 实现特征文件增量传输（JSON Patch 格式）— 当前每次下发完整签名 JSON，尚未做增量
- [x] 2.3.4 实现同步后一致性验证 — 以「逐文件内容哈希比对」实现：下载完成后本地重算哈希与签名 `content_hash` 比对，上传完成后以服务端重算哈希与本地比对，不一致则判失败并保留临时文件可重试（尚未做全库重扫再比较）
- [x] 2.3.5 实现批量文件下载（实际文件操作）— 差异列表勾选 + 全选，逐项串行下载，整体进度与当前文件展示，支持中止与续传
- [x] 2.3.6 实现手动删除管理 & 二次确认 — PC 已删除项仅提示，需显式勾选「删除本机」并二次确认后才删除；本机已删除项可「从 PC 恢复」
- [x] 2.3.7 实现可配置差异判定维度（取代「哈希值判断」单开关）：设置页新增「差异比较」区，file_size 恒参与（不可取消），content_hash 等可选维度以标签多选参与；两侧该维度均有效才启用、任一单侧缺值自动放行，启用维度取 AND。PC 端与手机端语义一致。见 `.trae/specs/configurable-diff-judgment`

### 2.4 PC 端设置增强
- [x] 2.4.1 实现「哈希计算开关」（默认关闭，与手机端对齐）：设置页新增开关，关闭时扫描跳过内容哈希，生成 `content_hash=''`、`content_hash_algo='none'`、`fingerprint_algorithms.content='none'`。见 `.trae/specs/add-pc-hash-debug-switches`
- [x] 2.4.2 实现可配置差异判定维度（PC 端）：设置页新增「差异比较」区，content_hash 可勾选参与；判定语义与手机端完全一致（file_size 恒参与 + 双侧有效才启用 + AND + 单侧缺值放行）。见 `.trae/specs/configurable-diff-judgment`
- [x] 2.4.3 实现「调试日志开关」（入口在顶部标签栏）：设置页新增开关，控制顶部「调试日志」第 4 页签的显示/隐藏（日志始终采集）；日志页与设置页支持拖动条滚动。见 `.trae/specs/add-pc-hash-debug-switches`

---

## 功能完成度追踪

```
阶段零           ████████████████████████  100%
  文档 & SOP      ████████████████████████  100%
  PC 骨架         ████████████████████████  100%
  PC 服务层       ████████████████████████  100%
  PC GUI          ████████████████████████  100%
  PC 验证 (CLI)   ████████████████████████  100%
  手机端搭建       ████████████████████████  100% (代码完成，需 Flutter 环境验证)

阶段一           ████████████████████████  100%
  PC 单元测试      ████████████████████████  100%
  手机端单元测试   ████████████████████████  100%

阶段二 (增强)     ████████████████████░░░░   83%
  2.1 高级匹配     ░░░░░░░░░░░░░░░░░░░░░░░░    0%
  2.2 局域网传输   ████████████████████░░░░   86% (余：连接密码/设备白名单)
  2.3 移动端增强   ███████████████████░░░░░   86% (余：签名增量传输)
  2.4 PC 设置增强  ████████████████████████  100%
  2.5 gRPC 双向同步████████████████████████  100%
```

> 说明：阶段二 2.5 的完成仅代表代码实现与客户端侧校验（PC 端数据面已通过 25 项端到端自检、Dart 侧 65 项单元测试通过、`flutter analyze` 无 error）；**真机（Android 实体设备 + 打包后 PC 端）的完整双向同步联调尚未执行**，需在具备设备的环境补验。