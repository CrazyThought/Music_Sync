# MusicSync 架构设计文档

## 1. 项目概述

MusicSync 是一个本地音乐库同步工具，帮助用户在电脑和手机之间管理音乐文件。当前阶段已实现两端独立扫描生成特征文件、差异比较与展示，支持「手动拷贝」与「局域网二维码配对」两种连接通道，并在此基础上实现了**局域网 gRPC 双向文件同步**（签名在线拉取 + 文件下载/上传 + 断点续传 + 冲突解决）。

网络通信采用**控制面 / 数据面分离**：

- **控制面（HTTP）**：发现、配对、握手、心跳，由 `services/qr_pairing.py`（PC）与 `qr_pairing_service.dart`（手机）承载；
- **数据面（gRPC）**：特征签名拉取与音频文件双向传输，由 `services/grpc_transport.py`（PC 服务端）与 `grpc_sync_client.dart`（手机客户端）承载；
- 两层通过握手产生的 `peer_id` 桥接鉴权：手机关联控制面与数据面，只有当前配对的对端可发起数据请求。

## 2. 系统架构

```
┌────────────────────────────┐   控制面(HTTP)     ┌────────────────────────────┐
│       PC 端 (Python)        │ ←───────────────→ │      手机端 (Flutter)       │
│                            │  二维码/握手/心跳   │                            │
│  ┌──────────────────────┐  │                   │  ┌──────────────────────┐  │
│  │ GUI (CustomTkinter)  │  │   数据面(gRPC)     │  │  Material Design     │  │
│  │  - 路径配置/扫描      │  │ ←───────────────→ │  │  - 主页/扫描/导入     │  │
│  │  - 结果展示/导出      │  │  签名/文件双向传输  │  │  - 差异展示           │  │
│  │  - 局域网连接卡片     │  │                   │  │  - 扫码连接           │  │
│  │    (二维码 + 传输进度)│  │                   │  │  - 双向同步页         │  │
│  └────────┬─────────────┘  │                   │  └────────┬─────────────┘  │
│           │                │                   │           │                │
│  ┌────────▼─────────────┐  │                   │  ┌────────▼─────────────┐  │
│  │  Service Layer       │  │                   │  │  Service Layer       │  │
│  │  - ScannerService    │  │                   │  │  - ScannerService    │  │
│  │  - SignatureService  │  │                   │  │  - SignatureService  │  │
│  │  - HashService       │  │                   │  │  - DiffService       │  │
│  │  - AudioMetaService  │  │                   │  │  - BidirectionalDiff │  │
│  │  - DiffService       │  │                   │  │  - SyncService       │  │
│  └────────┬─────────────┘  │                   │  └────────┬─────────────┘  │
│           │                │                   │           │                │
│  ┌────────▼─────────────┐  │                   │  ┌────────▼─────────────┐  │
│  │  Core Layer          │  │                   │  │  Storage Layer       │  │
│  │  - ConfigManager     │  │                   │  │  - Hive (配置)       │  │
│  │  - Logger            │  │                   │  │  - Hive (签名缓存)   │  │
│  └──────────────────────┘  │                   │  │  - Hive (同步基线)   │  │
│                            │                   │  └──────────────────────┘  │
│  ┌──────────────────────┐  │                   │  ┌──────────────────────┐  │
│  │  传输通道            │  │                   │  │  传输通道            │  │
│  │  - NoopTransport     │  │                   │  │  - QrPairingService  │  │
│  │  - QrPairingTransport│  │                   │  │    (控制面+心跳)      │  │
│  │    (HTTP 配对/心跳)   │  │                   │  │  - GrpcSyncClient    │  │
│  │  - GrpcSyncServer    │  │                   │  │    (数据面)          │  │
│  │    (gRPC 数据面)      │  │                   │  │  - ConnectionService │  │
│  └──────────────────────┘  │                   │  └──────────────────────┘  │
└────────────────────────────┘                   └────────────────────────────┘
```


## 3. 模块划分

### 3.1 PC 端模块

| 模块 | 路径 | 职责 |
|------|------|------|
| GUI 入口 | `main.py` | 程序启动、单实例检查、异常全局捕获 |
| 主窗口 | `app.py` | CustomTkinter 主窗口、标签页容器、状态栏、动态管理「调试日志」页签显隐 |
| 扫描页 | `pages/scan_page.py` | 路径配置、扫描触发、进度显示、概览卡片、局域网连接卡片；扫描完成后自动落盘签名文件（供数据面下发最新扫描结果） |
| 结果页 | `pages/result_page.py` | 分类表格、差异列表、导出操作 |
| 设置页 | `pages/settings_page.py` | 扫描参数、外观主题、哈希计算/调试日志开关（页面可滚动） |
| 调试日志页 | `pages/debug_log_page.py` | 只读实时日志浏览（环形缓冲轮询、自动滚动、清空） |
| 扫描引擎 | `services/scanner.py` | 文件夹遍历、增量扫描、并行处理、哈希计算开关 |
| 签名服务 | `services/signature.py` | 签名文件读写、格式校验 |
| 音频元数据 | `services/audio_meta.py` | ID3/Vorbis/FLAC 标签提取 |
| 哈希工具 | `services/hash_utils.py` | xxHash 计算、大文件分块策略 |
| 差异比较 | `services/diff_service.py` | PC 端自检差异比较 |
| 传输通道 | `services/sync_transport.py` | 中立传输通道抽象接口（`SyncTransport` + `DeviceInfo` + `PairingCode` + `NoopTransport`） |
| 二维码配对 | `services/qr_pairing.py` | 局域网二维码配对（单会话 HTTP 服务 + 一次性 token + 二维码渲染 + 心跳保活端点 + 握手响应回传 gRPC 端口） |
| gRPC 数据服务 | `services/grpc_transport.py` | 数据面服务端：签名下发（JSON 字节）、文件下发/接收（分块 + 断点续传）、`peer-id` 鉴权拦截器、路径越权防护、传输进度快照 |
| proto 契约 | `proto/musicsync.proto` | 双端 gRPC 服务与消息定义（唯一契约来源） |
| 生成代码 | `generated/` | 由 proto 生成的 Python stub（`musicsync_pb2.py` / `musicsync_pb2_grpc.py`） |
| 连接卡片/弹窗 | `pages/pairing_page.py` | 局域网连接卡片（`PairingCard`）与二维码弹窗（`PairingQrDialog`），内嵌于扫描页；同时管理 gRPC 服务生命周期并轮询展示传输进度 |
| 配置管理 | `core/config.py` | JSON 配置读写、降级容错、配对端口/gRPC 端口、哈希计算/调试日志开关字段 |
| 日志管理 | `core/logger.py` | 日志文件轮转、分级输出、内存环形缓冲（实时日志采集） |

### 3.2 手机端模块

| 模块 | 路径 | 职责 |
|------|------|------|
| 应用入口 | `lib/main.dart` | Flutter 应用启动、初始化 |
| 应用配置 | `lib/app.dart` | MaterialApp、路由、主题 |
| 数据模型 | `lib/models/` | 签名、文件条目、比较报告、配置 |
| 扫描服务 | `lib/services/scanner_service.dart` | 手机端文件夹扫描、统计音频总数与逐文件进度上报 |
| 音频元数据服务 | `lib/services/audio_metadata_service.dart` | 封装 Android `MediaMetadataRetriever`（经 `MainActivity` MethodChannel）按文件读取标题/艺术家/专辑/时长/比特率，映射为与 PC 端对齐的 `AudioMeta`（无标签/不支持格式时回退文件名） |
| 签名服务 | `lib/services/signature_service.dart` | 签名文件读写 |
| 差异服务 | `lib/services/diff_service.dart` | 三方差异比较 |
| 导入服务 | `lib/services/import_service.dart` | PC 签名文件导入 |
| 配置服务 | `lib/services/config_service.dart` | Hive 配置读写 |
| 传输接口 | `lib/services/sync_transport.dart` | 中立传输通道抽象接口（`SyncTransport`） |
| 二维码配对 | `lib/services/qr_pairing_service.dart` | 解析二维码 URL 完成 `/pair` 握手，持有会话发送 `/heartbeat` 心跳，并保留 gRPC 端口与基地址供数据面建连 |
| gRPC 数据客户端 | `lib/services/grpc_sync_client.dart` | 数据面客户端：签名拉取（JSON 字节 → 复用 `SignatureService` 校验）、文件下载/上传（分块 + 断点续传 + 哈希校验）、上传进度查询 |
| 设备信息模型 | `lib/models/device_info.dart` | 双端握手交换的设备元信息 |
| 连接状态服务 | `lib/services/connection_service.dart` | 单例全局连接状态（已连接对端信息 + 心跳定时保活 + 掉线自动断开 + gRPC 数据通道生命周期 + 通知 UI 刷新） |
| 双向差异服务 | `lib/services/bidirectional_diff_service.dart` | 以同步基线为参照的三方合并，产出方向化差异（下载/上传/冲突/删除提示/未变） |
| 同步编排服务 | `lib/services/sync_service.dart` | 计划装配、逐项串行传输、冲突裁决执行、断点续传、进度上报、基线写回 |
| 同步基线服务 | `lib/services/sync_baseline_service.dart` | 持久化「上次达成一致的签名快照」（Hive），供三方比较使用 |
| 同步计划模型 | `lib/models/sync_plan.dart` | 方向枚举、计划条目、冲突裁决方式、传输结果与批次汇总 |
| 扫码页 | `lib/screens/qr_scan_screen.dart` | 相机扫码 + 连接握手 + 写入全局连接状态 |
| 双向同步页 | `lib/screens/sync_screen.dart` | 准备（拉签名 + 本地重扫）→ 计划勾选与冲突裁决 → 传输进度 → 结果报告，含删除二次确认 |
| 调试日志服务 | `lib/services/debug_log_service.dart` | 本地日志文件存储（每次启动新建会话文件）、状态/操作/报错/信息分级、7 天清理、读取/清空/导出 |
| 日志条目模型 | `lib/models/debug_log_entry.dart` | 日志级别与日志条目 |
| 主页 | `lib/screens/home_screen.dart` | 状态概览、扫描进度展示、连接状态卡片（已连接时提供「开始同步」入口） |
| 扫描页 | `lib/screens/scan_screen.dart` | 本地扫描进度 |
| 导入页 | `lib/screens/import_screen.dart` | 导入 PC 签名 |
| 差异页 | `lib/screens/diff_screen.dart` | 差异分类展示 |
| 设置页 | `lib/screens/settings_screen.dart` | 路径配置、扫描参数、调试开关 |
| 日志弹窗 | `lib/widgets/debug_log_dialog.dart` | 日志展示、虚拟列表分页、实时刷新、导出、清空 |

### 3.3 构建/发布脚本

| 脚本 | 路径 | 用途 |
|------|------|------|
| proto 代码生成 | `scripts/generate_proto.ps1` | 依据 `proto/musicsync.proto` 生成两端 gRPC 代码（Python 侧写入 `music_sync_pc/generated/`，Dart 侧写入 `music_sync_app/lib/generated/`），并自动修正 Python 生成代码的包内相对导入。前置依赖：`grpcio-tools`（Python）与 `protoc_plugin`（`dart pub global activate protoc_plugin`）。**修改 proto 后必须重新执行本脚本。** |
| 一键发布脚本 | `scripts/build_release.ps1` | 读取 App 与 PC 当前版本 → 交互输入新版本名(x.y.z，App 构建号自动+1，PC 保持 x.y.z) → 前置校验 flutter 与 PyInstaller → 同步更新两端版本文件（App：`pubspec.yaml`、`settings_screen.dart`；PC：`constants.py`、`settings_page.py`）→ 依次执行 `flutter build apk --release` 与 `pyinstaller build.spec` → 统一归档 `MusicSync-Vxx.xx.xx.apk/.exe` 到项目根 `dist/`。版本来源：App 为 `pubspec.yaml` 的 `version` 字段（含构建号），PC 为 `constants.py` 的 `APP_VERSION`（仅 x.y.z）。 |

## 4. 数据流

```
音乐文件夹 ──扫描──→ [file_size, mtime] ──过滤──→ 变化文件列表
                                                      │
                                              ┌───────┴───────┐
                                              ▼               ▼
                                        xxHash 计算      ID3 标签提取
                                              │               │
                                              └───────┬───────┘
                                                      ▼
                                               文件条目组装
                                                      │
                                                      ▼
                                              pc_signature.json
                                                      │
                                              (手动传输到手机)
                                                      │
                                                      ▼
                                               差异比较引擎
                                              ┌───────┴───────┐
                                              ▼               ▼
                                        手机签名缓存      PC 签名
                                              │               │
                                              └───────┬───────┘
                                                      ▼
                                              SynReport (UI展示)
```

### 4.1 双向同步数据流（gRPC 数据面）

```
[手机] 开始同步
   │
   ├─(1) gRPC GetSignature ──────────────→ [PC] 读取 pc_signature.json，以 JSON 字节下发
   │                                          │
   │←─────────────────────────────────────────┘
   ├─(2) 本地重扫（ScannerService）→ 手机当前签名
   │
   ├─(3) 三方合并（BidirectionalDiffService）—— 判定顺序：
   │        ① 两侧都有 → 先直接比两端内容：一致即判「未变」（不变量，不受基线影响）
   │        ② 不一致 → 借基线定方向：仅 PC 变→下载 / 仅本机变→上传 / 都变→冲突
   │        ③ 仅一侧有 → 基线无则「新增」（可下载 / 可上传），基线有则「已删除」提示
   │        分类：下载 / 上传 / 冲突 / PC已删 / 本机已删 / 未变
   │
   ├─(4) 用户勾选 + 冲突裁决（保留 PC 版 / 保留手机版 / 都保留）
   │
   ├─(5) 逐项执行（SyncService）
   │        ├─ 下载：gRPC DownloadFile(offset) → 写 .musicsync-part → 校验哈希 → 改名落盘
   │        ├─ 上传：gRPC GetUploadStatus → UploadFile(offset) → 服务端 .part → 校验后落盘
   │        ├─ 冲突保留 PC 版：同下载；保留手机版：同上传；都保留：先本地另存副本再下载
   │        └─ 删除本机 / 从 PC 恢复（需用户显式勾选，删除前二次确认）
   │
   └─(6) 写回基线：本次「确认一致」的路径回写当前 PC 条目（含「未变」项，实现基线自愈），
            未完成 / 仅提示 / 未裁决项保留原基线条目
```

PC 端在数据传输期间通过 `GrpcSyncServer.progress` 暴露进度快照，连接卡片以 800ms 间隔轮询展示「当前传输文件 + 百分比」。

> **PC 端签名来源**：数据面 `GetSignature` 下发的签名取自 `output_folder/pc_signature.json`。该文件在**每次扫描完成后自动落盘**（点「开始扫描」即会更新），因此同步始终基于本机最新扫描结果；「导出签名文件」按钮保留用于手动重写同一文件。若只扫描不落盘（旧行为），数据面会继续下发上一次导出的旧签名，其 `file_size` / 路径可能已过期，从而把两端其实一致的文件误判为「需上传 / 需下载」。

> **方向判定不变量**：两侧内容一致的文件必定归为「未变」，绝不进入「下载到本机 / 上传到 PC」；基线仅用于「两端内容确实不一致」时区分谁该覆盖谁。每次同步还会把「本次一致」的路径回写基线（自愈），避免历史脏基线条目导致同一文件被反复误判方向。判定依据（原因、两侧大小、哈希是否有效、基线是否存在）会逐条写入调试日志，便于定位方向误判。

## 5. 技术选型理由

| 选择 | 理由 |
|------|------|
| Python 3.11+ | 跨平台、音频处理库丰富、开发效率高 |
| CustomTkinter 5.x | 现代化 Tkinter 封装、轻量（+2MB）、暗色主题 |
| mutagen | Python 音频元数据提取的事实标准库 |
| xxhash | 比 MD5 快 10 倍、碰撞概率满足本场景 |
| PyInstaller 6.x | 成熟的 Python 打包工具、单文件输出 |
| Flutter 3.x | 一套代码 Android/iOS、Material Design |
| Hive | Flutter 端轻量 NoSQL、无原生依赖 |
| qrcode + pillow | PC 端二维码图片生成 |
| mobile_scanner | 手机端相机扫码 |
| grpcio (Python) | 数据面服务端；原生双向流与流式传输，适配「下载 + 上传 + 断点续传」 |
| grpc + protobuf + fixnum (Dart) | 数据面客户端；由 `proto/musicsync.proto` 生成两端 stub，契约单点维护 |

## 6. 扩展接口设计

### 6.1 控制面 / 数据面分离

双端通过中立抽象接口预留传输能力，接口只表达「启动/停止/获取设备信息/生成配对」等能力语义，不绑定具体技术（HTTP 服务端、UDP 广播等），使发现/配对与传输解耦。当前提供两类实现：`NoopTransport`（未启用 / 手动拷贝兜底）与二维码配对实现。

在此之上，实际数据传输由独立的 gRPC 数据面承担，形成两层结构：

| 层次 | 职责 | PC 实现 | 手机实现 | 技术 |
|------|------|---------|----------|------|
| 控制面 | 发现、配对、握手、心跳、会话保活 | `services/qr_pairing.py` | `qr_pairing_service.dart` + `connection_service.dart` | HTTP（标准库 `http.server` / `dart:io`） |
| 数据面 | 特征签名下发、音频文件双向传输 | `services/grpc_transport.py` | `grpc_sync_client.dart` | gRPC（`grpcio` / `grpc` 包） |

两层的唯一耦合点是握手产生的 `peer_id`：HTTP 握手成功后 PC 端记录手机 `peer_id`，手机端在 gRPC metadata 中以 `peer-id` 回传该标识；PC 端鉴权拦截器校验一致才受理请求（不一致返回 `UNAUTHENTICATED`）。这种分离让已验证的配对/保活逻辑无需重写，同时数据面可独立演进。

```python
# PC 端：控制面接口（保持中立能力语义）
class SyncTransport(ABC):
    def start(self, host: str, port: int) -> None: ...
    def stop(self) -> None: ...
    def get_device_info(self) -> DeviceInfo: ...
    def create_pairing(self) -> PairingCode: ...
```

```dart
// 手机端：控制面接口
abstract class SyncTransport {
  Future<DeviceInfo> connect(Uri uri);
  Future<void> disconnect();
}
```

```proto
// 数据面契约（proto/musicsync.proto）
service MusicSync {
  rpc GetSignature(GetSignatureRequest) returns (SignatureResponse);   // 签名（JSON 字节）
  rpc DownloadFile(DownloadRequest) returns (stream FileChunk);         // 下载（断点续传）
  rpc UploadFile(stream FileChunk) returns (UploadResponse);            // 上传（断点续传）
  rpc GetUploadStatus(UploadStatusRequest) returns (UploadResponse);    // 续传偏移查询
}
```

数据面的两条安全约束：

- **鉴权**：所有 RPC 校验 `peer-id` metadata，未配对或非法一律拒绝；
- **路径越权防护**：`relative_path` 经规范化后必须仍位于音乐根目录内，否则拒绝（防路径遍历）。

### 6.2 二维码配对握手流程

1. **PC 端**：用户在扫描页下方「局域网连接」卡片点击「二维码连接」→ 弹出二维码弹窗，启动单会话 HTTP 服务与 gRPC 数据服务，并生成携带一次性 token 的二维码 `http://<ip>:<port>/pair?token=<rand>`（token 有效期 180 秒，握手成功后失效）。
2. **手机端**：用户点击主页「扫码连接」→ 请求相机权限 → 扫描二维码解析 URL。
3. **握手**：手机端以 POST 请求 `/pair?token=<rand>` 并在请求体回传本机 `DeviceInfo`，PC 端校验 token（无效/过期/已消费返回 401），成功后双方交换 `DeviceInfo`（端点类型/名称/版本/协议版本/对端 id），响应体附带 `grpc_port` 供手机端建立数据面通道。
4. **完成**：PC 端弹窗自动关闭、卡片展示对端设备信息（可「断开连接」复位）；手机端主页展示「已连接 PC + 设备信息 + 开始同步 + 断开」状态卡片（由全局 `ConnectionService` 驱动）；`ConnectionService` 同时按 `grpc_port` 建立并持有 `GrpcSyncClient`（PC 未启用数据面时按钮禁用并提示）。
5. **保活**：握手成功后手机端每 3 秒发送一次 `POST /heartbeat`（携带 peer_id），PC 端校验身份并刷新最近心跳时间，PC 端卡片每 3 秒轮询对端存活；任一端连续 9 秒未收到对端信号即判定掉线并自动复位为「连接已断开 / 未连接」状态，同时关闭 gRPC 数据通道。