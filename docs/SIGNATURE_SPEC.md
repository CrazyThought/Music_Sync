# 特征文件格式规范 v2.0

## 1. 概述

特征文件（signature file）是 MusicSync 系统的核心数据载体，用于描述一个音乐文件夹中所有音频文件的标识信息和元数据。PC 端生成此文件，手机端解析此文件并进行差异比较。

## 2. 文件格式

- 格式：JSON（UTF-8 编码，无 BOM）
- 缩进：2 空格（`indent=2`）
- 换行：LF（`\n`）
- 文件名约定：`pc_signature.json` / `phone_signature.json`

## 3. 完整结构

```json
{
  "format_version": "2.0",
  "generated_by": "MusicSync/PC/1.0.0",
  "generated_at": 1716123456789,
  "scan_root": "D:\\Music",
  "scan_summary": {
    "total_files": 12568,
    "total_size_bytes": 21474836480,
    "scan_duration_ms": 823
  },
  "files": [
    {
      "relative_path": "流行/周杰伦/晴天.mp3",
      "file_size": 8723456,
      "modified_at": 1715000000000,
      "content_hash": "a1b2c3d4e5f67890",
      "content_hash_algo": "xxh64",
      "audio_meta": {
        "title": "晴天",
        "artist": "周杰伦",
        "album": "叶惠美",
        "duration_ms": 269000,
        "bitrate_kbps": 320
      },
      "audio_fingerprint": null
    }
  ],
  "fingerprint_algorithms": {
    "content": "xxh64",
    "audio": "none"
  }
}
```

## 4. 字段定义

### 4.1 顶层字段

| 字段 | 类型 | 必须 | 说明 |
|------|------|------|------|
| `format_version` | string | ✅ | 固定值 `"2.0"`，用于校验兼容性 |
| `generated_by` | string | ✅ | 生成端标识，格式 `MusicSync/{端}/{版本}` |
| `generated_at` | number | ✅ | Unix 时间戳（毫秒），生成时间 |
| `scan_root` | string | ✅ | 扫描的根目录绝对路径 |
| `scan_summary` | object | ✅ | 扫描统计摘要 |
| `files` | array | ✅ | 文件条目列表，按 `relative_path` 字母序排列 |
| `fingerprint_algorithms` | object | ✅ | 使用的指纹算法声明 |

### 4.2 scan_summary 字段

| 字段 | 类型 | 必须 | 说明 |
|------|------|------|------|
| `total_files` | number | ✅ | 扫描到的音频文件总数 |
| `total_size_bytes` | number | ✅ | 所有音频文件的总字节数 |
| `scan_duration_ms` | number | ✅ | 扫描耗时（毫秒） |

### 4.3 files[] 条目字段

| 字段 | 类型 | 必须 | 说明 |
|------|------|------|------|
| `relative_path` | string | ✅ | 相对于 `scan_root` 的文件路径，使用 `/` 分隔符 |
| `file_size` | number | ✅ | 文件大小（字节） |
| `modified_at` | number | ✅ | 文件最后修改时间（Unix 毫秒时间戳） |
| `content_hash` | string | ✅ | 文件内容哈希值（16 进制字符串） |
| `content_hash_algo` | string | ✅ | 哈希算法标识，固定 `"xxh64"` |
| `audio_meta` | object | ✅ | 音频元数据对象 |
| `audio_fingerprint` | string\|null | ⭕ | 音频声学指纹，暂为 `null` |

### 4.4 audio_meta 字段

| 字段 | 类型 | 必须 | 说明 |
|------|------|------|------|
| `title` | string | ✅ | 曲目标题（取自 ID3/Vorbis 标签，无标签时用文件名） |
| `artist` | string | ✅ | 艺术家（无标签时为空字符串） |
| `album` | string | ⭕ | 专辑名（无标签时为 `null`） |
| `duration_ms` | number | ✅ | 音频时长（毫秒） |
| `bitrate_kbps` | number | ⭕ | 比特率（kbps），无损格式为 `null` |

## 5. 路径规范

- 所有路径分隔符统一使用 `/`（正斜杠），无论在哪个平台生成
- `relative_path` 不包含 `scan_root` 前缀
- 路径中的特殊字符（Unicode 等）直接保留，不做转义
- Windows 盘符（如 `D:\`）仅存在于 `scan_root` 字段中

## 6. 兼容性规则

解析端（手机端）必须遵循以下规则：

| 规则 | 说明 |
|------|------|
| 未知字段忽略 | 遇到 `files[]` 中未定义的字段时，静默忽略 |
| `format_version` 不匹配 | 主版本不同 → 拒绝解析，提示用户更新 |
| `format_version` 次版本不同 | 向前兼容，正常解析 |
| `content_hash_algo` 不匹配 | 拒绝解析，提示算法不兼容 |
| `audio_fingerprint` 为 null | 正常处理，不影响其他字段 |

## 7. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 2.0 | 2024-05 | 初始版本：完整字段定义、二级指纹、音频元数据 |