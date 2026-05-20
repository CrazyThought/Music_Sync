/// MaterialApp 配置、路由、主题。
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/import_screen.dart';
import 'screens/diff_screen.dart';
import 'screens/settings_screen.dart';

class MusicSyncApp extends StatelessWidget {
  const MusicSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicSync',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/scan': (_) => const ScanScreen(),
        '/import': (_) => const ImportScreen(),
        '/diff': (_) => const DiffScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}