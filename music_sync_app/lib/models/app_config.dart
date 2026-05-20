/// 应用配置模型 —— 以 JSON 形式存储在 Hive Box 中，无需代码生成。
class AppConfig {
  String musicFolderPath;
  bool autoDetectMusicFolder;
  String importFolderPath;
  List<String> scanExtensions;
  List<String> ignoredDirs;
  String themeMode;
  int lastScanTimestamp;

  AppConfig({
    this.musicFolderPath = '',
    this.autoDetectMusicFolder = true,
    this.importFolderPath = '',
    this.scanExtensions = const ['mp3', 'flac', 'wav', 'm4a', 'ogg'],
    this.ignoredDirs = const [],
    this.themeMode = 'dark',
    this.lastScanTimestamp = 0,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      musicFolderPath: json['musicFolderPath'] as String? ?? '',
      autoDetectMusicFolder: json['autoDetectMusicFolder'] as bool? ?? true,
      importFolderPath: json['importFolderPath'] as String? ?? '',
      scanExtensions: List<String>.from(json['scanExtensions'] ?? []),
      ignoredDirs: List<String>.from(json['ignoredDirs'] ?? []),
      themeMode: json['themeMode'] as String? ?? 'dark',
      lastScanTimestamp: json['lastScanTimestamp'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'musicFolderPath': musicFolderPath,
        'autoDetectMusicFolder': autoDetectMusicFolder,
        'importFolderPath': importFolderPath,
        'scanExtensions': scanExtensions,
        'ignoredDirs': ignoredDirs,
        'themeMode': themeMode,
        'lastScanTimestamp': lastScanTimestamp,
      };
}