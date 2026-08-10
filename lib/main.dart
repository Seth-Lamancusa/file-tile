import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_tile/file_tile.dart';

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
    return ChangeNotifierProvider(
      create: (_) => DesktopViewModel(),
      child: Consumer<DesktopViewModel>(
        builder: (context, viewModel, _) {
          return MaterialApp(
            title: 'File Tile',
            themeMode: viewModel.themeMode,
            theme: ThemeData(
              brightness: Brightness.light,
              useMaterial3: true,
              colorSchemeSeed: Colors.indigo,
              scaffoldBackgroundColor: FileTileColors.light.background,
              extensions: const [FileTileColors.light],
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              colorSchemeSeed: Colors.indigo,
              scaffoldBackgroundColor: FileTileColors.dark.background,
              extensions: const [FileTileColors.dark],
            ),
            home: const DesktopViewPage(),
          );
        },
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
