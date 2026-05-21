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
│   │   ├── hash_utils.py    # XXH3-64 & 大文件分块
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
git clone https://github.com/CrazyThought/Music_Sync.git
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

#### 环境准备

```bash
# 检查 Flutter 环境（必须）
flutter doctor

# 确认版本 ≥ 3.19
flutter --version
```

> \[!IMPORTANT]
> **Android SDK 配置**
>
> 构建 APK 需要 Android SDK。如果报 `No Android SDK found`：
>
> ```powershell
> # 方案 1：安装 Android Studio（推荐），自动配置 SDK
>
> # 方案 2：手动下载命令行工具
> # 1. 下载 cmdline-tools 解压到 D:\Android SDK\cmdline-tools
> # 2. 配置环境变量
> setx ANDROID_HOME "D:\Android SDK"
> # 3. 设置 Flutter SDK 路径
> flutter config --android-sdk "D:\Android SDK"
> # 4. 安装必要组件（需要 JDK 11+）
> & "D:\Android SDK\cmdline-tools\bin\sdkmanager.bat" "platform-tools" "build-tools;36.0.0" "platforms;android-36"
> ```
>
> 如果编译报 `requires compile against version 36`，检查 [android/app/build.gradle.kts](music_sync_app/android/app/build.gradle.kts) 中 `compileSdk = 36`。

#### 安装依赖 & 运行

```bash
cd music_sync_app

# 安装 Flutter 依赖
flutter pub get

# 连接 Android 设备或启动模拟器后运行
flutter run

# 以 release 模式运行（性能测试）
flutter run --release
```

## 开发命令速查

### PC 端 (Python)

```powershell
# 启动 GUI
python main.py
# 或
C:\Python313\python.exe main.py

# 运行测试
cd music_sync_pc
C:\Python313\python.exe -m pytest ..\tests\ -v

# 打包为 exe（阶段二）
pyinstaller build.spec --clean --noconfirm
```

### 手机端 (Flutter)

```bash
# 静态分析（零错误策略）
flutter analyze

# 运行所有测试
flutter test

# 运行指定测试文件
flutter test test/diff_service_test.dart

# 清理构建缓存（编译异常时首选）
flutter clean

# 重新获取依赖
flutter pub get

# 升级依赖到最新兼容版本
flutter pub upgrade

# 构建 debug APK（开发调试用）
flutter build apk --debug

# 构建 release APK（发布用）
flutter build apk --release

# 构建 Android App Bundle（上传 Google Play）
flutter build appbundle --release

# 构建 iOS（需 macOS + Xcode）
flutter build ios --release

# 启用桌面/Web 平台支持（可选）
flutter create . --platforms windows
```

### 项目清理

```powershell
# 一键清理编译缓存、Python 缓存、临时文件（不含 Gradle）
.\scripts\cleanup.ps1
```

## 可能遇到的问题

### Python 启动报 `ModuleNotFoundError: No module named 'customtkinter'`

最常见的多 Python 问题。PATH 中的 `python` 指向了未安装依赖的版本。

**解决**：

```powershell
# 方案 1：用完整路径（临时）
C:\Python313\python.exe main.py

# 方案 2：调整 PATH 顺序（永久）
# 将 C:\Python313 及 C:\Python313\Scripts 移到 PATH 最前面
```

### `xxhash` 安装报 `Microsoft Visual C++ 14.0 or greater is required`

安装 `xxhash==3.4.1` 时需要编译。

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

### Flutter 端 `flutter run` 报 `No supported devices connected`

没有连接 Android 设备或启动模拟器。如果要在 Windows 桌面运行：

```bash
cd music_sync_app
flutter create . --platforms windows
flutter run -d windows
```

### 构建 APK 报 `No Android SDK found`

参见上方「手机端初始化 - Android SDK 配置」章节。

### 构建 APK 报 `requires compile against version 36`

依赖库需要 `compileSdk ≥ 36`。检查并修改 `android/app/build.gradle.kts`：

```kotlin
android {
    compileSdk = 36  // 不要用 flutter.compileSdkVersion
    defaultConfig {
        targetSdk = 36
    }
}
```

修改后执行 `flutter clean` 清除缓存重新构建。

### 磁盘空间不足（C 盘被 Gradle/Flutter 缓存占满）

Flutter 编译和 Gradle 会在 C 盘累积大量缓存。快速清理：

```powershell
# 一键清理（推荐）
.\scripts\cleanup.ps1
```

#### Gradle 缓存手动清理

Gradle 构建缓存位于 `C:\Users\<用户名>\.gradle\`，以下是各子目录说明及是否可删除：

| 路径 | 大小 | 可删除 | 说明 |
| ---- | ---- | ------ | ---- |
| `caches\` | ~1.5 GB | **是** | 构建产物缓存，下次构建会自动重建 |
| ├ `caches\9.1.0\` | ~630 MB | 是 | 版本级编译缓存 |
| ├ `caches\modules-2\` | ~900 MB | 是 | 下载的依赖 jar/aar 缓存 |
| `wrapper\` | ~690 MB | **是** | Gradle wrapper 下载缓存，Flutter 会自动重新下载 |
| `daemon\` | ~12 MB | **是** | Gradle 守护进程日志和状态文件 |
| `.tmp\` | <1 MB | **是** | 临时文件 |

**如果完全删除 `.gradle\` 目录**：下次 `flutter build` 时会自动重新下载 Gradle 和所有依赖，耗时约 3-5 分钟，但可释放约 2.2 GB 空间。

### PC 端文件复制到手机后差异显示为「更新」

阶段一已修复。根因是手机端扫描器未计算内容哈希（`contentHash` 为空），与 PC 端哈希不匹配。现已统一为 XXH3-64 算法，内容相同的文件正确归入「未变」。

### 特征文件版本不兼容

PC 端和手机端必须使用相同的特征文件格式版本（当前 `2.0`）。如果版本不匹配，手机端会拒绝解析并提示更新。

## 测试

### 测试结构

```
tests/                          # PC 端单元测试 (pytest)
├── test_hash_utils.py          # XXH3-64 正确性 & 分块策略
├── test_audio_meta.py          # 正常标签 & 损坏标签 & 无标签
├── test_scanner.py             # 全量扫描 & 增量扫描 & 过滤
├── test_signature.py           # 生成 & 校验 & 版本兼容
├── test_diff_service.py        # 新增/删除/更新/未变
└── test_config.py              # 加载 & 保存 & 降级

music_sync_app/test/            # 手机端单元测试 (flutter test)
├── diff_service_test.dart      # 各种比较场景
├── signature_service_test.dart # 序列化 & 反序列化
├── config_service_test.dart    # 配置模型 JSON 往返
└── scanner_service_test.dart   # 哈希计算 & 扫描集成
```

### 运行测试

```powershell
# PC 端
cd music_sync_pc
C:\Python313\python.exe -m pytest ..\tests\ -v

# 手机端
cd music_sync_app
flutter test
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
| PC 哈希  | xxhash (XXH3-64)         | 比 MD5 快 10 倍的内容指纹    |
| PC 打包  | PyInstaller 6.x          | 单文件 exe 输出           |
| 手机 UI  | Flutter 3.x + Material 3 | 跨平台移动端               |
| 手机哈希   | xxh3 (XXH3-64)           | 纯 Dart 实现，与 PC 端一致   |
| 手机存储   | Hive                     | 轻量 NoSQL 配置存储        |