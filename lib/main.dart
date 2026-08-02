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
    return ChangeNotifierProvider(
      create: (_) => DesktopViewModel(),
      child: Consumer<DesktopViewModel>(
        builder: (context, viewModel, _) {
          return MaterialApp(
            title: 'Stitch Desktop Grid',
            themeMode: viewModel.themeMode,
            theme: ThemeData(
              brightness: Brightness.light,
              useMaterial3: true,
              colorSchemeSeed: Colors.indigo,
              scaffoldBackgroundColor: StitchColors.light.background,
              extensions: const [StitchColors.light],
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              colorSchemeSeed: Colors.indigo,
              scaffoldBackgroundColor: StitchColors.dark.background,
              extensions: const [StitchColors.dark],
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
