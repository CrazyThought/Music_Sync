/// MusicSync 手机端入口 - 最小化测试版本。
library music_sync_app;

import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text('Hello MusicSync'),
      ),
    ),
  ));
}
