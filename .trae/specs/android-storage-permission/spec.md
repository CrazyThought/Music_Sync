# Android 存储权限申请 Spec

## Why
当前 Flutter 手机端应用在执行文件扫描、导入等操作时需要访问设备存储空间，但应用中既未声明 Android 存储权限，也未在运行时向用户请求权限授权。这导致在 Android 设备上扫描音乐文件夹或导入文件时会静默失败，用户无法正常使用核心功能。

## What Changes
- 在 AndroidManifest.xml 中声明存储读取权限（兼容 Android 13+ 和旧版本）
- 在应用启动时（main.dart 或 HomeScreen 初始化时）主动请求存储权限
- 在扫描/导入操作前检查权限状态，若无权限则引导用户授权

## Impact
- Affected specs: 无
- Affected code:
  - `music_sync_app/android/app/src/main/AndroidManifest.xml` — 添加权限声明
  - `music_sync_app/lib/main.dart` — 添加权限初始化逻辑
  - `music_sync_app/lib/screens/home_screen.dart` — 扫描/导入前检查权限

## ADDED Requirements

### Requirement: AndroidManifest 权限声明
系统 SHALL 在 AndroidManifest.xml 中声明以下存储权限：
- `READ_MEDIA_AUDIO`（Android 13+）
- `READ_EXTERNAL_STORAGE`（Android 12 及以下）
- `MANAGE_EXTERNAL_STORAGE`（可选，备用方案）

#### Scenario: Android 13+ 设备
- **WHEN** 应用安装在 Android 13+ 设备上
- **THEN** 使用 `READ_MEDIA_AUDIO` 权限访问音频文件

#### Scenario: Android 12 及以下设备
- **WHEN** 应用安装在 Android 12 及以下设备上
- **THEN** 使用 `READ_EXTERNAL_STORAGE` 权限访问文件

### Requirement: 应用启动时权限请求
系统 SHALL 在应用进入主页前检查存储权限状态，如果未授权则弹出系统权限对话框请求用户授权。

#### Scenario: 首次安装启动
- **WHEN** 用户首次打开应用
- **THEN** 弹出系统权限请求对话框，询问存储访问权限

#### Scenario: 权限已被授予
- **WHEN** 用户已授予存储权限
- **THEN** 直接进入主页，不弹出权限对话框

#### Scenario: 权限被拒绝
- **WHEN** 用户拒绝权限请求
- **THEN** 进入主页但显示提示信息，告知用户需要在设置中开启权限才能扫描音乐

### Requirement: 操作前权限校验
系统 SHALL 在执行扫描或文件导入操作前验证权限状态，若权限未授予则提示用户开启。

#### Scenario: 扫描时无权限
- **WHEN** 用户点击"扫描本机音乐"但存储权限未授予
- **THEN** 显示 SnackBar 提示用户开启存储权限，并提供跳转设置页面的入口