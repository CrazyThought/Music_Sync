# MusicSync 开发标准操作流程 (SOP)

## 1. 环境要求

### 1.1 PC 端开发环境

| 项目 | 版本/工具 | 说明 |
|------|----------|------|
| Python | 3.11+ | 使用 f-string、`pathlib`、类型注解 |
| pip | 23.0+ | 包管理 |
| venv | 内置 | 虚拟环境隔离 |
| PyInstaller | 6.x | 打包工具，仅发布时使用 |

```bash
cd music_sync_pc
python -m venv .venv
source .venv/bin/activate      # Linux/macOS
.venv\Scripts\activate         # Windows
pip install -r requirements.txt
```

### 1.2 手机端开发环境

| 项目 | 版本/工具 | 说明 |
|------|----------|------|
| Flutter SDK | 3.19+ | 跨平台框架 |
| Dart | 3.3+ | 编程语言 |
| Android Studio | Hedgehog+ | Android 构建 |
| Xcode | 15+ | iOS 构建（仅 macOS） |

```bash
cd music_sync_app
flutter pub get
flutter run
```

## 2. 编码规范

### 2.1 Python 编码规范

**强制规则：**

```python
# ============================================================
# 文件头：模块说明 + 编码声明 + 类型注解
# ============================================================
"""文件扫描引擎 - 递归遍历音乐目录并收集音频文件元数据。"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

# ============================================================
# 导入顺序：标准库 → 第三方库 → 项目内部
# 每组之间空一行，组内按字母序排列
# ============================================================


# ============================================================
# 命名规范：
#   类名：PascalCase        → MusicScanner, ConfigManager
#   函数/方法：snake_case    → scan_folder(), compute_hash()
#   常量：UPPER_SNAKE        → AUDIO_EXTENSIONS, MAX_WORKERS
#   私有方法：_snake_case     → _quick_filter(), _build_index()
#   模块名：snake_case       → audio_meta.py, hash_utils.py
# ============================================================


# ============================================================
# 类型注解：所有公开方法必须有完整的参数和返回值类型注解
# ============================================================
def compute_hash(file_path: Path, file_size: int) -> str:
    ...


# ============================================================
# 文档字符串：所有公开类和公开方法必须有 docstring
# ============================================================
class MusicScanner:
    """音乐文件夹扫描器。

    负责递归遍历指定目录，收集所有符合扩展名条件的音频文件，
    并提取文件元数据和内容哈希。

    Attributes:
        root_path: 扫描的根目录路径。
        max_workers: 并行处理的线程数。
    """

    def scan(self, previous_signature: dict[str, Any] | None = None) -> dict[str, Any]:
        """执行扫描并返回签名数据。

        Args:
            previous_signature: 上次扫描的签名数据，用于增量过滤。None 表示全量扫描。

        Returns:
            符合 SIGNATURE_SPEC v2.0 的签名字典。

        Raises:
            FileNotFoundError: 当 root_path 不存在时。
            PermissionError: 当无权限读取目录时。
        """
        ...
```

**禁止事项：**
- 禁止使用裸 `except:`，必须指定具体异常类型
- 禁止在循环中使用 `+` 拼接字符串，使用 `"".join()` 或 f-string
- 禁止在 `__init__.py` 中编写业务逻辑
- 禁止使用 `os.path`，统一使用 `pathlib.Path`
- 禁止直接 `print()` 调试，统一走 `logger`

### 2.2 Dart 编码规范

**强制规则：**

```dart
// ============================================================
// 文件头：模块说明
// ============================================================
/// 差异比较引擎 - 对两个特征文件进行三方比较，生成同步报告。

// ============================================================
// 导入顺序：dart: → package: → 相对路径
// 每组之间空一行
// ============================================================

// ============================================================
// 命名规范：
//   类名/枚举/类型：PascalCase     → DiffService, SyncReport
//   函数/方法/变量：camelCase      → computeDiff(), fileList
//   常量：lowerCamelCase           → audioExtensions, maxWorkers  (Dart 风格)
//   私有成员：_camelCase           → _buildIndex(), _matchByMeta()
//   文件名：snake_case             → diff_service.dart
// ============================================================

// ============================================================
// 文档注释：使用 ///，所有公开 API 必须有文档
// ============================================================
/// 对 PC 端签名和手机端签名进行比较。
///
/// 返回 [SyncReport] 包含四种变更分类：新增、更新、移动、待删除。
class DiffService {
  /// 执行差异比较。
  ///
  /// [pcSignature] PC 端最新的特征文件数据。
  /// [phoneSignature] 手机端当前的特征文件数据。
  SyncReport compare(Signature pcSignature, Signature phoneSignature) {
    // ...
  }
}
```

**禁止事项：**
- 禁止使用 `dynamic`，除非确实无法确定类型
- 禁止在 `build()` 方法中执行业务逻辑
- 禁止硬编码字符串用于 UI，统一使用国际化或常量
- 禁止在 StatefulWidget 中直接修改状态，必须通过 `setState`

## 3. 分支与版本策略

### 3.1 分支规范

```
main                    ← 生产分支，始终可打包
  └── develop           ← 开发主分支
        ├── feat/pc-scan-gui     ← PC 端扫描 GUI
        ├── feat/pc-signature    ← 特征文件生成
        ├── feat/app-scan        ← 手机端扫描
        ├── feat/app-diff        ← 手机端差异比较
        └── fix/*                ← 紧急修复分支
```

### 3.2 版本号规范

遵循 `主版本.次版本.修订号`：

| 类型 | 变更 | 示例 |
|------|------|------|
| 主版本 | 不兼容的 API 变更 | 2.0.0：特征文件格式重构 |
| 次版本 | 向后兼容的新功能 | 1.1.0：新增音频指纹 |
| 修订号 | 向后兼容的 Bug 修复 | 1.0.1：修复大文件哈希错误 |

### 3.3 Commit 规范

```
<type>(<scope>): <subject>

可选类型：
  feat      新功能
  fix       错误修复
  refactor  重构（不改变功能）
  docs      文档变更
  style     格式调整（不影响代码运行）
  chore     构建/工具变更

示例：
  feat(scanner): 实现 xxHash-64 增量哈希计算
  fix(gui): 修复进度条在 Windows 高 DPI 下显示错位
  docs(spec): 更新特征文件字段说明
```

## 4. 测试规范

### 4.1 测试层级

| 层级 | 目录 | 覆盖目标 | 工具 |
|------|------|---------|------|
| 单元测试 | `tests/unit/` | service 层纯函数 | pytest |
| 集成测试 | `tests/integration/` | 扫描→签名→导出完整流程 | pytest |
| GUI 测试 | `tests/gui/` | 页面交互正确性 | 手动 + pytest-qt(可选) |

### 4.2 测试数据

```
tests/
├── fixtures/
│   ├── small_music_lib/       # 小型测试音乐库（10-15 首）
│   │   ├── pop/
│   │   │   ├── test_song_1.mp3
│   │   │   └── test_song_2.flac
│   │   └── rock/
│   │       └── test_song_3.mp3
│   ├── expected_signature.json  # 已知正确输出
│   └── corrupted_tags.mp3       # 损坏标签的测试文件
```

### 4.3 运行测试

```bash
# PC 端
cd music_sync_pc
pytest tests/ -v --cov=services --cov-report=html

# 手机端
cd music_sync_app
flutter test
```

### 4.4 测试覆盖率要求

| 模块 | 最低覆盖率 | 说明 |
|------|-----------|------|
| `services/scanner.py` | 90% | 核心逻辑 |
| `services/signature.py` | 85% | 格式正确性 |
| `services/hash_utils.py` | 95% | 纯函数，易覆盖 |
| `services/audio_meta.py` | 80% | 标签提取容错 |
| `core/config.py` | 85% | 配置读写 |
| GUI 层 | 不做要求 | 手动验收 |

## 5. 发布流程

### 5.1 PC 端发布检查清单

- [ ] 所有单元测试通过
- [ ] 在 Windows 10/11 上手动运行完整扫描验证
- [ ] 确认 `config.json` 降级逻辑生效（删除 config 后程序正常启动）
- [ ] 确认打包后 exe 独立运行（不依赖 Python 环境）
- [ ] 检查 `requirements.txt` 版本号是否锁定（无 `>=` 号）
- [ ] 更新 `generated_by` 中的版本号

### 5.2 打包命令

```bash
cd music_sync_pc
pyinstaller build.spec --clean --noconfirm
# 输出: dist/MusicSync.exe
```

### 5.3 手机端发布检查清单

- [ ] `flutter analyze` 无警告
- [ ] `flutter test` 全部通过
- [ ] Android 实体机测试扫描和导入流程
- [ ] 签名文件版本兼容性校验生效

## 6. 代码审查要点

每次 PR 必须经过以下维度的审查：

1. **安全性**：无硬编码密码、无文件越权访问、无路径遍历风险
2. **性能**：大文件夹扫描不阻塞 UI、哈希计算使用分块策略
3. **容错性**：损坏文件不导致整个扫描中断、异常有友好的用户提示
4. **一致性**：命名风格、文件结构、错误处理模式与现有代码一致
5. **文档**：新增公开方法有 docstring、复杂逻辑有注释