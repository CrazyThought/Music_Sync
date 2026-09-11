# MusicSync

本地音乐库同步工具，帮助用户在电脑和手机之间管理音乐文件。

当前版本 **v2.0.0**，主要能力：

- **局域网直连同步**：手机扫描 PC 端二维码完成配对，两端自动比对音乐并按方向同步（支持断点续传与哈希校验）
- **离线签名比对**：PC 端扫描生成特征文件，手机端导入后比对差异（无需连接，两种方式可并行使用）

## 功能概览

| 功能 | 说明 |
| ---- | ---- |
| 音乐扫描 | 递归扫描音乐目录，提取文件元数据、标签与内容哈希（XXH3-64） |
| 特征文件 | 生成符合 `SIGNATURE_SPEC v2.0` 的 JSON 签名；PC 端扫描完成后自动落盘 |
| 差异比对 | 按「新增 / 更新 / 删除 / 未变」分类展示两端差异 |
| 二维码配对 | 手机扫码与 PC 建连，一次性令牌 + 单会话服务 |
| 连接保活 | 手机端每 3 秒心跳，任一端连续 9 秒无信号自动断线并复位状态 |
| 双向同步 | 基于「基线 + 两端现状」分类为下载 / 上传 / 冲突 / 已删 / 未变，可逐项勾选执行 |
| 断点续传 | 上传、下载均支持中断续传；完成后校验内容哈希，失败可单独重试 |
| 安全防护 | 数据通道校验配对身份；文件路径限制在音乐库目录内 |
| 调试日志 | 分级日志（状态 / 操作 / 报错 / 信息），两端均可查看与导出 |

## 使用说明

### 整体流程

**方式一：局域网直连同步（推荐）**

```
PC 端生成配对二维码 → 手机端扫码配对 → 两端建立连接（心跳保活）
→ 手机端进入「同步」页准备（拉取 PC 签名 + 本地重扫）
→ 查看差异分类与冲突 → 勾选执行 → 双向传输（断点续传 + 哈希校验）→ 结果报告
```

**方式二：离线签名比对（无需连接）**

```
PC 端扫描音乐库 → 生成特征文件(pc_signature.json) → 传输到手机
→ 手机端导入 → 手机扫描本地音乐 → 差异比对 → 查看新增/更新/删除
```

### PC 端 (Windows)

1. **启动程序**：双击 `MusicSync.exe`，或在 `music_sync_pc` 目录执行 `python main.py`
2. **选择音乐文件夹**：在「扫描」页点击浏览，选择你的音乐目录
3. **开始扫描**：点击「开始扫描」，等待进度条完成
4. **特征文件自动落盘**：扫描完成后自动写入输出目录（落盘失败不影响扫描，状态栏会给出提示）；「导出签名文件」按钮保留为手动重写入口
5. **查看结果**：切换到「结果」页，按「新增/更新/删除」分类查看差异明细
6. **连接手机**：「扫描」页的「局域网连接」卡片提供「二维码连接」按钮，点击生成配对二维码；连接成功后该卡片展示对端设备信息与实时传输进度（当前文件 + 百分比）

### 手机端 (Android)

**局域网同步**

1. 打开应用主页，点击右上角「扫码连接 PC」，扫描 PC 端展示的配对二维码
2. 配对成功后主页显示连接状态卡片（任一端断开或超时约 9 秒会自动复位）
3. 点击「开始同步」进入同步页，等待「准备」完成（拉取 PC 签名 + 本地重扫）
4. 查看差异分类与冲突项，按需勾选；冲突可逐条选择保留 PC 版 / 保留手机版 / 都保留
5. 开始传输，可随时中止（保留临时文件以便续传）；完成后查看结果报告，失败项可重试

**离线比对**

1. **导入 PC 特征文件**：将 PC 端生成的 `pc_signature.json` 传输到手机
2. **扫描本地音乐**：在应用中导入特征文件，自动扫描手机本地音乐
3. **查看差异**：比对完成后按「新增/更新/删除」分类展示

### 设置

- **扫描设置**：并行线程数、大文件阈值（分块哈希）、文件扩展名过滤
- **差异比较**：`file_size` 恒参与（不可取消）；`content_hash` 等维度可勾选，两端语义一致（双侧有效才启用，单侧缺值自动放行，启用维度取 AND）
- **哈希计算开关**：默认关闭，关闭时扫描跳过内容哈希
- **调试日志开关**：控制日志入口的显示（日志始终采集，仅控制是否显示入口）
- **外观设置**：亮色 / 暗色主题切换

## 项目结构

```
Music_Sync/
├── docs/
│   ├── ARCHITECTURE.md      # 架构设计文档
│   ├── ROADMAP.md           # 开发路线图 & 代办事项
│   └── SIGNATURE_SPEC.md    # 特征文件格式规范 v2.0
├── proto/
│   └── musicsync.proto      # gRPC 服务契约（双端代码生成的唯一来源）
├── scripts/
│   ├── build_release.ps1    # 一键发布构建（App + PC）
│   ├── cleanup.ps1          # 清理编译缓存与临时文件
│   ├── generate_proto.ps1   # 由 proto 生成双端 gRPC 代码
│   └── verify_hash_consistency.py  # 双端哈希一致性校验
├── SOP.md                   # 开发标准操作流程
├── README.md
├── music_sync_pc/           # PC 端 (Python / CustomTkinter)
│   ├── main.py              # 程序入口 & 单实例检查
│   ├── app.py               # 主窗口 & 标签页容器
│   ├── build.spec           # PyInstaller 打包配置（图标 icon.ico）
│   ├── icon.ico             # 应用图标
│   ├── core/                # config.py 配置管理 / logger.py 日志管理
│   ├── generated/           # proto 生成的 Python stub（勿手改）
│   ├── services/            # 服务层
│   │   ├── scanner.py       # 文件扫描引擎（增量/并行）
│   │   ├── signature.py     # 特征文件读写与校验
│   │   ├── diff_service.py  # 差异比较引擎
│   │   ├── hash_utils.py    # XXH3-64 & 大文件分块
│   │   ├── audio_meta.py    # 音频元数据提取 (mutagen)
│   │   ├── sync_transport.py# 传输通道抽象接口
│   │   ├── qr_pairing.py    # 二维码配对（单会话 HTTP 服务 + 心跳）
│   │   └── grpc_transport.py# gRPC 数据面（签名/上传/下载/鉴权）
│   ├── pages/               # 扫描 / 结果 / 局域网连接 / 设置 / 调试日志
│   ├── utils/               # constants.py 常量 / file_utils.py 文件工具
│   ├── tests/               # unit/ + integration/
│   └── requirements.txt     # Python 依赖
└── music_sync_app/          # 手机端 (Flutter)
    ├── lib/
    │   ├── main.dart        # 应用入口
    │   ├── app.dart         # MaterialApp & 路由
    │   ├── generated/       # proto 生成的 Dart stub（勿手改）
    │   ├── models/          # 数据模型（签名/文件条目/同步计划/设备信息…）
    │   ├── screens/         # 主页/扫描/导入/差异/扫码/同步/设置
    │   ├── services/        # 扫描/签名/差异/连接/配对/gRPC 客户端/同步编排/基线/日志
    │   ├── widgets/         # debug_log_dialog.dart 日志弹窗
    │   └── utils/           # 常量
    ├── test/                # Dart 单元测试
    └── pubspec.yaml         # Flutter 依赖
```

## 环境要求

| 端  | 语言/工具       | 最低版本  | 说明                     |
| -- | ----------- | ----- | ---------------------- |
| PC | Python      | 3.11+ | 打包与运行均使用            |
| PC | pip         | 23.0+ | 包管理                    |
| PC | PyInstaller | 6.x   | 打包单文件 exe（仅发布时使用）      |
| 手机 | Flutter SDK | 3.19+ | 跨平台框架                  |
| 手机 | Dart        | 3.3+  | 编程语言                   |
| 双端 | 代码生成        | —     | 修改 `proto/` 后需 `grpcio-tools` + `protoc_plugin` |

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

> [!IMPORTANT]
> **常见问题：多 Python 版本冲突**
>
> 如果机器上有多个 Python（如 MSYS2 自带的 3.12 + 系统安装的 3.13），`python` 命令可能指向没有依赖的版本。
>
> ```powershell
> # 检查当前使用的 Python
> python --version
> where.exe python
>
> # 如果 python 指向了错误的版本，用完整路径启动（示例）：
> C:\Python313\python.exe music_sync_pc\main.py
> ```

#### 启动 PC GUI

```powershell
# 在 music_sync_pc 目录下
python main.py
```

#### 服务层快速验证（无需 GUI）

```powershell
python -c "
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

> [!IMPORTANT]
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

### 4. 生成 gRPC 代码

`music_sync_pc/generated/` 与 `music_sync_app/lib/generated/` 均由 `proto/musicsync.proto` 生成，**修改 proto 后必须重新生成**：

```powershell
# 前置依赖：Python 侧 grpcio-tools，Dart 侧 protoc_plugin
#   pip install grpcio-tools
#   dart pub global activate protoc_plugin
.\scripts\generate_proto.ps1
```

## 开发命令速查

### PC 端 (Python)

```powershell
cd music_sync_pc

# 启动 GUI
python main.py

# 运行测试（测试位于 music_sync_pc/tests）
python -m pytest tests/ -v

# 打包为 exe（推荐写法：不依赖 pyinstaller 是否在 PATH 中）
python -m PyInstaller build.spec --clean --noconfirm
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

### 发布构建

```powershell
# 交互式选择构建范围：
#   1) 全量构建：Android APK + PC exe，需要输入新版本号(x.y.z)
#   2) 仅 App 构建：只出 APK，沿用当前版本号
#   3) 仅 PC 构建：只出 exe，沿用当前版本号
.\scripts\build_release.ps1
```

仅「全量构建」会输入新版本号并同步更新两端版本文件；「仅 App」「仅 PC」不修改任何版本文件，产物按当前版本号归档到 `dist/`（同名产物会被覆盖）。

### 项目清理

```powershell
# 一键清理编译缓存、Python 缓存、临时文件（不含 Gradle）
.\scripts\cleanup.ps1
```

## 可能遇到的问题

### 打包 PC 端报 `无法将"pyinstaller"项识别为 cmdlet、函数、脚本文件或可运行程序的名称`

`pyinstaller.exe` 所在目录（Python 安装目录下的 `Scripts\`）不在 PATH 中。改用模块方式调用即可，无需改环境变量：

```powershell
python -m PyInstaller build.spec --clean --noconfirm
```

> 发布脚本 `scripts\build_release.ps1` 已内置该回退：优先 `pyinstaller`，找不到则自动使用 `python -m PyInstaller`。

### 打包 PC 端报 `CopyIcons failed ... EndUpdateResourceW ... 拒绝访问 (WinError 5)`

PyInstaller 生成 exe 时需要对 `dist\MusicSync.exe` **原地写入图标/清单/版本资源**，若被安全软件拦截就会返回"拒绝访问"，且重试 20 次后仍失败。

- 该故障**通常是间歇性的**：重跑一次构建往往即可通过
- 若频繁复现，请让 IT 将项目目录（至少 `music_sync_pc\dist`）与 `python.exe` 加入终端安全软件的白名单
- 构建失败后 `dist\MusicSync.exe` 可能是只有几百 KB 的半成品，**不要拿它去发布**

### Flutter 构建报 `Could not start thread DartWorker: 22` / `Building native assets for package:objective_c failed`

Dart VM 在编译依赖包的 native assets 钩子时创建线程失败（多为偶发），随后报 `Bad state: Generating kernel failed!`。

可依次尝试：

```bash
flutter clean
# 重新构建；若仍复现，可临时关闭 native assets：
flutter config --no-enable-native-assets
```

若长期复现，建议将 Flutter 从 master/dev 通道切回 stable。

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
# 会自动安装有 wheel 的最新版（如 3.8.x）
```

### Flutter 端 `flutter pub get` 报错

确保 Flutter SDK 版本 ≥ 3.19：

```bash
flutter --version
flutter upgrade  # 如需升级
```

**Flutter端 `Got TLS error trying to find package` 报错**

```Shell
# 切换镜像源
$env:PUB_HOSTED_URL="https://pub.dev"; $env:FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"; flutter pub get
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

| 路径                   | 大小       | 可删除   | 说明                                 |
| -------------------- | -------- | ----- | ---------------------------------- |
| `caches\`            | ~1.5 GB  | **是** | 构建产物缓存，下次构建会自动重建                   |
| ├ `caches\9.1.0\`    | ~630 MB  | 是     | 版本级编译缓存                            |
| ├ `caches\modules-2\` | ~900 MB  | 是     | 下载的依赖 jar/aar 缓存                   |
| `wrapper\`           | ~690 MB  | **是** | Gradle wrapper 下载缓存，Flutter 会自动重新下载 |
| `daemon\`            | ~12 MB   | **是** | Gradle 守护进程日志和状态文件                 |
| `.tmp\`              | <1 MB    | **是** | 临时文件                               |

**如果完全删除 `.gradle\` 目录**：下次 `flutter build` 时会自动重新下载 Gradle 和所有依赖，耗时约 3-5 分钟，但可释放约 2.2 GB 空间。

### 手机端连接后长时间显示「已连接」但对方已退出

心跳保活已覆盖该场景：两端任一侧连续 9 秒收不到心跳即判定掉线，自动断开并复位连接状态。若仍出现，请检查两端是否已同时升级到同一版本。

### PC 端文件复制到手机后差异显示为「更新」

阶段一已修复。根因是手机端扫描器未计算内容哈希（`contentHash` 为空），与 PC 端哈希不匹配。现已统一为 XXH3-64 算法，内容相同的文件正确归入「未变」。

### 特征文件版本不兼容

PC 端和手机端必须使用相同的特征文件格式版本（当前 `2.0`）。如果版本不匹配，手机端会拒绝解析并提示更新。

## 测试

### 测试结构

```
music_sync_pc/tests/                  # PC 端单元/集成测试 (pytest)
├── unit/
│   ├── test_config.py                # 配置加载 & 保存 & 降级
│   ├── test_scanner.py              # 全量扫描 & 增量扫描 & 过滤
│   └── test_diff_service.py         # 新增/删除/更新/移动/未变
└── integration/
    └── test_grpc_transport.py       # gRPC 数据面（签名/上传/下载/鉴权）

music_sync_app/test/                  # 手机端单元测试 (flutter test)
├── audio_metadata_service_test.dart
├── bidirectional_diff_service_test.dart
├── config_service_test.dart
├── debug_log_service_test.dart
├── diff_service_test.dart
└── scanner_service_test.dart
```

### 运行测试

```powershell
# PC 端
cd music_sync_pc
python -m pytest tests/ -v

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
| [SIGNATURE_SPEC.md](docs/SIGNATURE_SPEC.md) | 特征文件 JSON 格式规范 v2.0 |
| [SOP.md](SOP.md)                             | 编码规范、分支策略、测试规范、发布流程 |

## 技术栈

| 层      | 技术                         | 用途                     |
| ------ | -------------------------- | ---------------------- |
| PC GUI | CustomTkinter 5.x          | 现代化 Tkinter 封装         |
| PC 音频  | mutagen                    | ID3/Vorbis/FLAC 标签提取   |
| PC 哈希  | xxhash (XXH3-64)           | 比 MD5 快 10 倍的内容指纹      |
| PC 配对  | qrcode                     | 生成配对二维码                |
| PC 通信  | grpcio + protobuf          | gRPC 数据面：签名/上传/下载/鉴权   |
| PC 打包  | PyInstaller 6.x            | 单文件 exe 输出             |
| 手机 UI  | Flutter 3.x + Material 3   | 跨平台移动端                 |
| 手机 扫码  | mobile_scanner             | 相机扫码配对                 |
| 手机 通信  | grpc + protobuf            | gRPC 数据面客户端            |
| 手机 哈希  | xxh3 (XXH3-64)             | 纯 Dart 实现，与 PC 端一致     |
| 手机 存储  | Hive                       | 配置与同步基线持久化             |
| 手机 权限  | permission_handler         | 存储 / 相机权限              |
