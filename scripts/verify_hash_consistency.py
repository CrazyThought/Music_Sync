"""验证 Python xxhash.xxh3_64 与 Dart xxh3 包对相同文件的一致性。"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import xxhash

# Windows 控制台可能使用 GBK 编码，强制使用 UTF-8 以支持 emoji 输出
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT_ROOT = Path(__file__).resolve().parent.parent
TMP = Path(tempfile.gettempdir()) / "xxh3_test.bin"

# 常见的 Dart SDK 安装路径
_DART_HINTS = [
    # 从 PATH 查找
    lambda: shutil.which("dart"),
    # Flutter SDK 自带的 Dart
    lambda: shutil.which("flutter"),
]


def _find_dart() -> str | None:
    """查找 Dart 可执行文件，找不到返回 None。"""
    dart = shutil.which("dart")
    if dart:
        return dart

    # 尝试通过 flutter 定位 dart
    flutter = shutil.which("flutter")
    if flutter:
        dart = Path(flutter).resolve().parent / "dart"
        if dart.with_suffix(".exe" if sys.platform == "win32" else "").exists():
            return str(dart.with_suffix(".exe" if sys.platform == "win32" else ""))

    # 常见安装路径
    common_paths = [
        Path.home() / "flutter" / "bin" / "dart",
        Path("C:/flutter/bin/dart"),
        Path("D:/flutter/bin/dart"),
        Path.home() / "snap" / "flutter" / "common" / "flutter" / "bin" / "dart",
    ]
    for p in common_paths:
        if sys.platform == "win32":
            p = p.with_suffix(".exe")
        if p.exists():
            return str(p)

    return None


def python_hash(filepath: Path) -> str:
    h = xxhash.xxh3_64()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()


def dart_hash(filepath: Path, project_dir: Path, dart_exe: str) -> str:
    """用 Dart xxh3 包计算哈希，返回十六进制字符串。"""
    dart_code = '''import 'dart:io';
import 'package:xxh3/xxh3.dart';

void main(List<String> args) {
  final file = File(args[0]);
  final bytes = file.readAsBytesSync();
  final hash = xxh3Stream()..update(bytes);
  print(hash.digestString().padLeft(16, '0'));
}
'''
    dart_file = project_dir / "_hash_test.dart"
    dart_file.write_text(dart_code, encoding="utf-8")
    try:
        result = subprocess.run(
            [dart_exe, "run", str(dart_file), str(filepath)],
            capture_output=True, text=True,
            cwd=str(project_dir),
        )
        if result.returncode != 0:
            raise RuntimeError(f"Dart 执行失败:\n{result.stderr.strip()}")
        return result.stdout.strip()
    finally:
        dart_file.unlink(missing_ok=True)


def main():
    print("=== XXH3-64 跨语言哈希一致性验证 ===")

    content = b"Hello, MusicSync! Cross-language hash test. " * 100
    TMP.write_bytes(content)
    print(f"测试文件: {TMP} ({len(content)} bytes)")

    py_hash = python_hash(TMP)
    print(f"Python (xxhash.xxh3_64): {py_hash}")

    dart_exe = _find_dart()
    if dart_exe is None:
        print("\n⚠ 未找到 Dart SDK，跳过 Dart 端验证。")
        print("  请安装 Flutter/Dart SDK 并确保 dart 命令在 PATH 中。")
    else:
        print(f"Dart SDK: {dart_exe}")
        flutter_dir = PROJECT_ROOT / "music_sync_app"
        dart_hash_val = dart_hash(TMP, flutter_dir, dart_exe)
        print(f"Dart   (xxh3Stream):    {dart_hash_val}")

        if py_hash == dart_hash_val:
            print("\n✅ 一致性验证通过！Python 与 Dart XXH3-64 哈希一致。")
        else:
            print(f"\n❌ 一致性验证失败！哈希不匹配。")
            print(f"   Python: {py_hash}")
            print(f"   Dart:   {dart_hash_val}")
            TMP.unlink(missing_ok=True)
            sys.exit(1)

    TMP.unlink(missing_ok=True)


if __name__ == "__main__":
    main()