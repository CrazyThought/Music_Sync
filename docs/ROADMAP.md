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
- [ ] 0.4.5 PyInstaller 打包验证：exe 在纯净 Windows 运行（需桌面 Windows 环境）

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
- [ ] 2.2.1 实现 `NetworkTransport` — UDP 广播发现
- [ ] 2.2.2 实现 `HttpServer` — FastAPI 只读文件服务
- [ ] 2.2.3 实现手机端 `discoverPeers()` & `fetchRemoteSignature()`
- [ ] 2.2.4 实现文件断点续传下载
- [ ] 2.2.5 实现连接密码验证 & 设备白名单

### 2.3 移动端增强
- [ ] 2.3.1 实现扫描进度条：先获取文件总数，按当前进度实时展示扫描进度，并在进度条上显示当前正在扫描的文件名
- [ ] 2.3.2 实现调试日志显示：设置界面添加开关，开启后在设置按钮旁显示日志按钮，点击弹出日志弹窗（含状态、操作、报错等处理后便于理解与问题定位的详细信息）
- [ ] 2.3.3 实现特征文件增量传输（JSON Patch 格式）
- [ ] 2.3.4 实现同步后一致性验证（本地重扫 + 比较）
- [ ] 2.3.5 实现批量文件下载（实际文件操作）
- [ ] 2.3.6 实现手动删除管理 & 二次确认

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

阶段一 (当前)     ████████████████████████  100%
  PC 单元测试      ████████████████████████  100%
  手机端单元测试   ████████████████████████  100%

阶段二 (增强)     ░░░░░░░░░░░░░░░░░░░░░░░░    0%
```