# MusicSync

本地音乐库同步工具，帮助用户在电脑和手机之间管理音乐文件。当前阶段实现 PC 端扫描生成特征文件、手机端导入后差异比较展示。

## 项目结构

```
Music_Sync/
├── docs/
│   ├── ARCHITECTURE.md      # 架构设计文档
│   ├── ROADMAP.md           # 开发路线图 & 代办事项
│   └── SIGNATURE_SPEC.md    # 特征文件格式规范 v2.0
├── SOP.md                   # 开发标准操作流程
├── music_sync_pc/           # PC 端 (Python / CustomTkinter)
│   ├── main.py              # 程序入口 & 单实例检查
│   ├── app.py               # 主窗口 & 标签页容器
│   ├── core/                # 核心模块
│   │   ├── config.py        # 配置管理器 (JSON 持久化)
│   │   └── logger.py        # 日志管理器 (文件轮转)
│   ├── services/            # 服务层
│   │   ├── scanner.py       # 文件扫描引擎 (增量/并行)
│   │   ├── signature.py     # 特征文件读写与校验
│   │   ├── diff_service.py  # 差异比较引擎
│   │   ├── hash_utils.py    # xxHash-64 & 大文件分块
│   │   ├── audio_meta.py    # 音频元数据提取 (mutagen)
│   │   └── sync_transport.py # 预留: 局域网传输接口
│   ├── pages/               # GUI 页面
│   │   ├── scan_page.py     # 扫描页 (路径选择 + 进度)
│   │   ├── result_page.py   # 结果页 (差异分类表格)
│   │   └── settings_page.py # 设置页 (参数 + 外观)
│   ├── utils/               # 工具模块
│   │   ├── constants.py     # 常量定义
│   │   └── file_utils.py    # 文件系统工具
│   └── requirements.txt     # Python 依赖
└── music_sync_app/          # 手机端 (Flutter)
    ├── lib/
    │   ├── main.dart        # 应用入口
    │   ├── app.dart         # MaterialApp & 路由
    │   ├── models/          # 数据模型
    │   ├── screens/         # 页面 (主页/扫描/导入/差异/设置)
    │   ├── services/        # 服务层
    │   └── utils/           # 常量 & 工具
    └── pubspec.yaml         # Flutter 依赖
```

## 环境要求

| 端  | 语言          | 最低版本  | 说明      |
| -- | ----------- | ----- | ------- |
| PC | Python      | 3.11+ | 推荐 3.13 |
| PC | pip         | 23.0+ | 包管理     |
| 手机 | Flutter SDK | 3.19+ | 跨平台框架   |
| 手机 | Dart        | 3.3+  | 编程语言    |

## 快速开始

### 1. 克隆项目

```bash
git clone <repo-url>
cd Music_Sync
```

### 2. PC 端初始化

#### 安装依赖

```powershell
# 进入 PC 端目录
cd music_sync_pc

# 安装依赖（注意：必须使用带 customtkinter 的 Python）
pip install -r requirements.txt
```

> \[!IMPORTANT]
> **常见问题：多 Python 版本冲突**
>
> 如果机器上有多个 Python（如 MSYS2 自带的 3.12 + 系统安装的 3.13），`python` 命令可能指向没有依赖的版本。
>
> ```powershell
> # 检查当前使用的 Python
> python --version
> where.exe python
>
> # 如果 python 指向了错误的版本，用完整路径启动：
> C:\Python313\python.exe music_sync_pc\main.py
> ```

#### 启动 PC GUI

```powershell
# 在 music_sync_pc 目录下
python main.py

# 或指定 Python 路径：
C:\Python313\python.exe music_sync_pc\main.py
```

#### 服务层快速验证（无需 GUI）

```powershell
C:\Python313\python.exe -c "
import sys; sys.path.insert(0, '.')
from core.config import ConfigManager
from services.scanner import MusicScanner
from services.signature import validate_signature
from pathlib import Path

# 配置
cfg = ConfigManager()
print('主题:', cfg.theme, '线程数:', cfg.max_workers)

# 扫描测试（替换为你的音乐目录）
scanner = MusicScanner(Path('D:/Music'))
result = scanner.scan()
print('扫描到', result['scan_summary']['total_files'], '个文件')
validate_signature(result)
print('签名校验通过')
"
```

### 3. 手机端初始化

```bash
cd music_sync_app

# 安装 Flutter 依赖
flutter pub get

# 运行
flutter run
```

> \[!NOTE]
> 手机端需要 [Flutter SDK](https://docs.flutter.dev/get-started/install) 和 Android Studio / Xcode 环境。

## 开发命令速查

### PC 端 (Python)

```powershell
# 启动 GUI
python main.py
# 或
C:\Python313\python.exe main.py

# 运行测试（阶段一完成后可用）
pytest tests/ -v --cov=services --cov-report=html

# 打包为 exe
pyinstaller build.spec --clean --noconfirm
```

### 手机端 (Flutter)

```bash
# 静态分析
flutter analyze

# 运行测试
flutter test

# 构建 APK
flutter build apk
```

## 可能遇到的问题

### Python 启动报 `ModuleNotFoundError: No module named 'customtkinter'`

这是最常见的多 Python 问题。PATH 中的 `python` 指向了未安装依赖的版本。

**解决**：

```powershell
# 方案 1：用完整路径（临时）
C:\Python313\python.exe main.py

# 方案 2：调整 PATH 顺序（永久）
# 将 C:\Python313 及 C:\Python313\Scripts 移到 PATH 最前面
```

### `pathlib.Path` 无法识别

需要 Python 3.11+，检查版本：

```powershell
python --version
```

### `xxhash` 安装报 `Microsoft Visual C++ 14.0 or greater is required`

> 发生于安装 `xxhash==3.4.1` 时需要编译。

**解决**：使用带预编译 wheel 的新版本：

```powershell
pip install xxhash
# 会自动安装有 wheel 的最新版（如 3.7.0）
```

### Flutter 端 `flutter pub get` 报错

确保 Flutter SDK 版本 ≥ 3.19：

```bash
flutter --version
flutter upgrade  # 如需升级
```

### 特征文件版本不兼容

PC 端和手机端必须使用相同的特征文件格式版本（当前 `2.0`）。如果版本不匹配，手机端会拒绝解析并提示更新。

## 测试

### 测试结构

```
music_sync_pc/
└── tests/
    ├── unit/              # 单元测试 (pytest)
    ├── integration/       # 集成测试
    ├── gui/               # GUI 测试 (手动/pytest-qt)
    └── fixtures/          # 测试用音乐文件
```

### 测试覆盖率要求

| 模块                       | 最低覆盖率 |
| ------------------------ | ----- |
| `services/scanner.py`    | 90%   |
| `services/hash_utils.py` | 95%   |
| `services/signature.py`  | 85%   |
| `services/audio_meta.py` | 80%   |
| `core/config.py`         | 85%   |

## 文档

| 文档                                           | 说明                  |
| -------------------------------------------- | ------------------- |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md)      | 系统架构、模块划分、数据流、技术选型  |
| [ROADMAP.md](docs/ROADMAP.md)                | 开发路线图、待办事项、完成度追踪    |
| [SIGNATURE\_SPEC.md](docs/SIGNATURE_SPEC.md) | 特征文件 JSON 格式规范 v2.0 |
| [SOP.md](SOP.md)                             | 编码规范、分支策略、测试规范、发布流程 |

## 技术栈

| 层      | 技术                       | 用途                   |
| ------ | ------------------------ | -------------------- |
| PC GUI | CustomTkinter 5.x        | 现代化 Tkinter 封装       |
| PC 音频  | mutagen                  | ID3/Vorbis/FLAC 标签提取 |
| PC 哈希  | xxhash                   | 比 MD5 快 10 倍的内容指纹    |
| PC 打包  | PyInstaller 6.x          | 单文件 exe 输出           |
| 手机 UI  | Flutter 3.x + Material 3 | 跨平台移动端               |
| 手机存储   | Hive                     | 轻量 NoSQL 配置存储        |

