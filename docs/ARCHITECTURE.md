# MusicSync 架构设计文档

## 1. 项目概述

MusicSync 是一个本地音乐库同步工具，帮助用户在电脑和手机之间管理音乐文件。当前阶段已实现两端独立扫描生成特征文件、差异比较与展示，并支持「手动拷贝」与「局域网二维码配对」两种连接通道。网络文件传输与文件操作留待后续扩展。

## 2. 系统架构

```
┌──────────────────────────┐  手动拷贝/二维码配对 ┌──────────────────────────┐
│      PC 端 (Python)       │  ────────────────→  │    手机端 (Flutter)       │
│                          │  pc_signature.json   │                          │
│  ┌────────────────────┐  │                     │  ┌────────────────────┐  │
│  │  GUI (CustomTkinter)│  │                     │  │  Material Design   │  │
│  │  - 路径配置          │  │                     │  │  - 主页概览        │  │
│  │  - 扫描触发          │  │                     │  │  - 本地扫描        │  │
│  │  - 结果展示          │  │                     │  │  - 导入签名        │  │
│  │  - 设置管理          │  │                     │  │  - 差异展示        │  │
│  │  - 局域网连接        │  │                     │  │  - 扫码连接        │  │
│  └────────┬───────────┘  │                     │  └────────┬───────────┘  │
│           │              │                     │           │              │
│  ┌────────▼───────────┐  │                     │  ┌────────▼───────────┐  │
│  │  Service Layer     │  │                     │  │  Service Layer     │  │
│  │  - ScannerService  │  │                     │  │  - ScannerService  │  │
│  │  - SignatureService│  │                     │  │  - SignatureService│  │
│  │  - HashService     │  │                     │  │  - DiffService     │  │
│  │  - AudioMetaService│  │                     │  │  - ConfigService   │  │
│  └────────┬───────────┘  │                     │  └────────┬───────────┘  │
│           │              │                     │           │              │
│  ┌────────▼───────────┐  │                     │  ┌────────▼───────────┐  │
│  │  Core Layer        │  │                     │  │  Storage Layer     │  │
│  │  - ConfigManager   │  │                     │  │  - Hive (配置)     │  │
│  │  - Logger          │  │                     │  │  - Hive (签名缓存) │  │
│  └────────────────────┘  │                     │  └────────────────────┘  │
│                          │                     │                          │
│  ┌────────────────────┐  │                     │  ┌────────────────────┐  │
│  │  传输通道           │  │                     │  │  传输通道           │  │
│  │  SyncTransport      │  │                     │  │  SyncTransport     │  │
│  │  - NoopTransport   │  │                     │  │  - QrPairingService │  │
│  │  - QrPairingTransport│ │                    │  │                    │  │
│  └────────────────────┘  │                     │  └────────────────────┘  │
└──────────────────────────┘                     └──────────────────────────┘
```

## 3. 模块划分

### 3.1 PC 端模块

| 模块 | 路径 | 职责 |
|------|------|------|
| GUI 入口 | `main.py` | 程序启动、单实例检查、异常全局捕获 |
| 主窗口 | `app.py` | CustomTkinter 主窗口、标签页容器、状态栏、动态管理「调试日志」页签显隐 |
| 扫描页 | `pages/scan_page.py` | 路径配置、扫描触发、进度显示、概览卡片、局域网连接卡片 |
| 结果页 | `pages/result_page.py` | 分类表格、差异列表、导出操作 |
| 设置页 | `pages/settings_page.py` | 扫描参数、外观主题、哈希计算/调试日志开关（页面可滚动） |
| 调试日志页 | `pages/debug_log_page.py` | 只读实时日志浏览（环形缓冲轮询、自动滚动、清空） |
| 扫描引擎 | `services/scanner.py` | 文件夹遍历、增量扫描、并行处理、哈希计算开关 |
| 签名服务 | `services/signature.py` | 签名文件读写、格式校验 |
| 音频元数据 | `services/audio_meta.py` | ID3/Vorbis/FLAC 标签提取 |
| 哈希工具 | `services/hash_utils.py` | xxHash 计算、大文件分块策略 |
| 差异比较 | `services/diff_service.py` | PC 端自检差异比较 |
| 传输通道 | `services/sync_transport.py` | 中立传输通道抽象接口（`SyncTransport` + `DeviceInfo` + `PairingCode` + `NoopTransport`） |
| 二维码配对 | `services/qr_pairing.py` | 局域网二维码配对（单会话 HTTP 服务 + 一次性 token + 二维码渲染） |
| 连接卡片/弹窗 | `pages/pairing_page.py` | 局域网连接卡片（`PairingCard`）与二维码弹窗（`PairingQrDialog`），内嵌于扫描页 |
| 配置管理 | `core/config.py` | JSON 配置读写、降级容错、哈希计算/调试日志开关字段 |
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
| 二维码配对 | `lib/services/qr_pairing_service.dart` | 解析二维码 URL 并完成 `/pair` 握手（POST 回传本机设备信息） |
| 设备信息模型 | `lib/models/device_info.dart` | 双端握手交换的设备元信息 |
| 连接状态服务 | `lib/services/connection_service.dart` | 单例全局连接状态（已连接对端信息 + 通知 UI 刷新） |
| 扫码页 | `lib/screens/qr_scan_screen.dart` | 相机扫码 + 连接握手 + 写入全局连接状态 |
| 调试日志服务 | `lib/services/debug_log_service.dart` | 本地日志文件存储（每次启动新建会话文件）、状态/操作/报错/信息分级、7 天清理、读取/清空/导出 |
| 日志条目模型 | `lib/models/debug_log_entry.dart` | 日志级别与日志条目 |
| 主页 | `lib/screens/home_screen.dart` | 状态概览、扫描进度展示、连接状态卡片 |
| 扫描页 | `lib/screens/scan_screen.dart` | 本地扫描进度 |
| 导入页 | `lib/screens/import_screen.dart` | 导入 PC 签名 |
| 差异页 | `lib/screens/diff_screen.dart` | 差异分类展示 |
| 设置页 | `lib/screens/settings_screen.dart` | 路径配置、扫描参数、调试开关 |
| 日志弹窗 | `lib/widgets/debug_log_dialog.dart` | 日志展示、虚拟列表分页、实时刷新、导出、清空 |

### 3.3 构建/发布脚本

| 脚本 | 路径 | 用途 |
|------|------|------|
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

## 6. 扩展接口设计

双端通过中立抽象接口预留传输能力，接口只表达「启动/停止/获取设备信息/生成配对」等能力语义，不绑定具体技术（HTTP 服务端、UDP 广播等），使发现/配对与传输解耦。当前提供两类实现：`NoopTransport`（未启用 / 手动拷贝兜底）与二维码配对实现。

```python
# PC 端
class SyncTransport(ABC):
    def start(self, host: str, port: int) -> None: ...
    def stop(self) -> None: ...
    def get_device_info(self) -> DeviceInfo: ...
    def create_pairing(self) -> PairingCode: ...
```

```dart
// 手机端
abstract class SyncTransport {
  Future<DeviceInfo> connect(Uri uri);
  Future<void> disconnect();
}
```

### 6.1 二维码配对握手流程

1. **PC 端**：用户在扫描页下方「局域网连接」卡片点击「二维码连接」→ 弹出二维码弹窗，启动单会话 HTTP 服务并生成携带一次性 token 的二维码 `http://<ip>:<port>/pair?token=<rand>`（token 有效期 180 秒，握手成功后失效）。
2. **手机端**：用户点击主页「扫码连接」→ 请求相机权限 → 扫描二维码解析 URL。
3. **握手**：手机端以 POST 请求 `/pair?token=<rand>` 并在请求体回传本机 `DeviceInfo`，PC 端校验 token（无效/过期/已消费返回 401），成功后双方交换 `DeviceInfo`（端点类型/名称/版本/协议版本/对端 id）。
4. **完成**：PC 端弹窗自动关闭、卡片展示对端设备信息（可「断开连接」复位）；手机端主页展示「已连接 PC + 设备信息 + 断开」状态卡片（由全局 `ConnectionService` 驱动）；后续签名拉取与文件同步将在交换后的会话上扩展。