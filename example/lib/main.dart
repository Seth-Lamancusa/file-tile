import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stitch_desktop_grid/stitch_desktop_grid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize path service with home directory
  final homeDir = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];

  if (homeDir != null) {
    await PathService.init(homeDir);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desktop Grid Example',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: ChangeNotifierProvider(
        create: (_) => DesktopViewModel(),
        child: const DesktopViewPage(),
      ),
    );
  }
}

class DesktopViewPage extends StatelessWidget {
  const DesktopViewPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const DesktopView();
  }
}
