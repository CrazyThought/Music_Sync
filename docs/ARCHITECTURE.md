# MusicSync 架构设计文档

## 1. 项目概述

MusicSync 是一个本地音乐库同步工具，帮助用户在电脑和手机之间管理音乐文件。当前阶段仅实现两端独立扫描生成特征文件、手动导入后进行差异比较和展示的功能。网络传输和文件操作留待后续扩展。

## 2. 系统架构

```
┌──────────────────────────┐     手动拷贝     ┌──────────────────────────┐
│      PC 端 (Python)       │  ─────────────→  │    手机端 (Flutter)       │
│                          │  pc_signature.json │                          │
│  ┌────────────────────┐  │                   │  ┌────────────────────┐  │
│  │  GUI (CustomTkinter)│  │                   │  │  Material Design   │  │
│  │  - 路径配置          │  │                   │  │  - 主页概览        │  │
│  │  - 扫描触发          │  │                   │  │  - 本地扫描        │  │
│  │  - 结果展示          │  │                   │  │  - 导入签名        │  │
│  │  - 设置管理          │  │                   │  │  - 差异展示        │  │
│  └────────┬───────────┘  │                   │  └────────┬───────────┘  │
│           │              │                   │           │              │
│  ┌────────▼───────────┐  │                   │  ┌────────▼───────────┐  │
│  │  Service Layer     │  │                   │  │  Service Layer     │  │
│  │  - ScannerService  │  │                   │  │  - ScannerService  │  │
│  │  - SignatureService│  │                   │  │  - SignatureService│  │
│  │  - HashService     │  │                   │  │  - DiffService     │  │
│  │  - AudioMetaService│  │                   │  │  - ConfigService   │  │
│  └────────┬───────────┘  │                   │  └────────┬───────────┘  │
│           │              │                   │           │              │
│  ┌────────▼───────────┐  │                   │  ┌────────▼───────────┐  │
│  │  Core Layer        │  │                   │  │  Storage Layer     │  │
│  │  - ConfigManager   │  │                   │  │  - Hive (配置)     │  │
│  │  - Logger          │  │                   │  │  - Hive (签名缓存) │  │
│  └────────────────────┘  │                   │  └────────────────────┘  │
│                          │                   │                          │
│  ┌────────────────────┐  │                   │  ┌────────────────────┐  │
│  │  预留扩展接口       │  │                   │  │  预留扩展接口       │  │
│  │  SyncTransport     │  │                   │  │  SyncTransport     │  │
│  │  (当前空实现)       │  │                   │  │  (当前空实现)       │  │
│  └────────────────────┘  │                   │  └────────────────────┘  │
└──────────────────────────┘                   └──────────────────────────┘
```

## 3. 模块划分

### 3.1 PC 端模块

| 模块 | 路径 | 职责 |
|------|------|------|
| GUI 入口 | `main.py` | 程序启动、单实例检查、异常全局捕获 |
| 主窗口 | `app.py` | CustomTkinter 主窗口、标签页容器、状态栏 |
| 扫描页 | `pages/scan_page.py` | 路径配置、扫描触发、进度显示、概览卡片 |
| 结果页 | `pages/result_page.py` | 分类表格、差异列表、导出操作 |
| 设置页 | `pages/settings_page.py` | 扫描参数、外观主题 |
| 扫描引擎 | `services/scanner.py` | 文件夹遍历、增量扫描、并行处理 |
| 签名服务 | `services/signature.py` | 签名文件读写、格式校验 |
| 音频元数据 | `services/audio_meta.py` | ID3/Vorbis/FLAC 标签提取 |
| 哈希工具 | `services/hash_utils.py` | xxHash 计算、大文件分块策略 |
| 差异比较 | `services/diff_service.py` | PC 端自检差异比较 |
| 配置管理 | `core/config.py` | JSON 配置读写、降级容错 |
| 日志管理 | `core/logger.py` | 日志文件轮转、分级输出 |

### 3.2 手机端模块

| 模块 | 路径 | 职责 |
|------|------|------|
| 应用入口 | `lib/main.dart` | Flutter 应用启动、初始化 |
| 应用配置 | `lib/app.dart` | MaterialApp、路由、主题 |
| 数据模型 | `lib/models/` | 签名、文件条目、比较报告、配置 |
| 扫描服务 | `lib/services/scanner_service.dart` | 手机端文件夹扫描 |
| 签名服务 | `lib/services/signature_service.dart` | 签名文件读写 |
| 差异服务 | `lib/services/diff_service.dart` | 三方差异比较 |
| 导入服务 | `lib/services/import_service.dart` | PC 签名文件导入 |
| 配置服务 | `lib/services/config_service.dart` | Hive 配置读写 |
| 调试日志服务 | `lib/services/debug_log_service.dart` | 本地日志文件存储（每次启动新建会话文件）、状态/操作/报错/信息分级、7 天清理、读取/清空/导出 |
| 日志条目模型 | `lib/models/debug_log_entry.dart` | 日志级别与日志条目 |
| 主页 | `lib/screens/home_screen.dart` | 状态概览 |
| 扫描页 | `lib/screens/scan_screen.dart` | 本地扫描进度 |
| 导入页 | `lib/screens/import_screen.dart` | 导入 PC 签名 |
| 差异页 | `lib/screens/diff_screen.dart` | 差异分类展示 |
| 设置页 | `lib/screens/settings_screen.dart` | 路径配置、扫描参数、调试开关 |
| 日志弹窗 | `lib/widgets/debug_log_dialog.dart` | 日志展示、虚拟列表分页、实时刷新、导出、清空 |

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

## 6. 扩展接口设计

所有未来功能通过抽象接口预留，当前返回空实现或抛出 `UnimplementedError`：

```python
# PC 端预留
class SyncTransport(ABC):
    def start_server(self) -> None: ...
    def stop_server(self) -> None: ...
    def get_peers(self) -> list[str]: ...
```

```dart
// 手机端预留
abstract class SyncTransport {
  Future<List<String>> discoverPeers();
  Future<Signature> fetchRemoteSignature(String peerId);
  Future<void> downloadFiles(String peerId, List<String> paths, String dest);
}
```