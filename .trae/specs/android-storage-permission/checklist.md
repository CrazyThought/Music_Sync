* [x] AndroidManifest.xml 包含 `READ_MEDIA_AUDIO` 权限声明

* [x] AndroidManifest.xml 包含 `READ_EXTERNAL_STORAGE` 权限声明（maxSdkVersion="32"）

* [x] 存在 `permission_service.dart` 文件，包含权限请求和状态查询方法

* [x] `main.dart` 在 `runApp` 前调用权限请求

* [x] `home_screen.dart` 的 `_scanPhone()` 方法在扫描前检查权限

* [x] 无权限时显示 SnackBar 提示并提供跳转设置的入口

* [x] `pubspec.yaml` 中已包含 `permission_handler` 依赖

