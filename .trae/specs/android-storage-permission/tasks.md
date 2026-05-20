# Tasks

- [x] Task 1: 在 AndroidManifest.xml 中声明存储权限
  - [x] 1.1 添加 `READ_MEDIA_AUDIO` 权限（Android 13+）
  - [x] 1.2 添加 `READ_EXTERNAL_STORAGE` 权限（Android 12 及以下，添加 `maxSdkVersion="32"`）
  - [x] 1.3 添加 `MANAGE_EXTERNAL_STORAGE` 权限（可选备用方案）

- [x] Task 2: 创建权限服务 `permission_service.dart`
  - [x] 2.1 封装 `permission_handler` 插件的权限请求与状态查询
  - [x] 2.2 封装根据 Android 版本区分不同权限的逻辑
  - [x] 2.3 提供 `requestStoragePermission()` 和 `hasStoragePermission()` 方法

- [x] Task 3: 在应用启动时请求权限（修改 main.dart）
  - [x] 3.1 在 `runApp` 之前调用 `PermissionService.requestStoragePermission()`
  - [x] 3.2 根据权限状态决定是否显示引导提示

- [x] Task 4: 在主页扫描/导入操作前添加权限校验（修改 home_screen.dart）
  - [x] 4.1 `_scanPhone()` 方法中检查权限，无权限时弹出提示
  - [x] 4.2 提示中包含"前往设置"按钮，引导用户开启权限

# Task Dependencies
- Task 2 可与 Task 1 并行执行
- Task 3 依赖 Task 2
- Task 4 依赖 Task 2