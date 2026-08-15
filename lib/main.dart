import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_tile/file_tile.dart';
import 'package:file_tile/src/services/linux_url_handler_registrar.dart';

/// Fired by the Linux runner (linux/runner/my_application.cc) when this
/// process is launched -- or, if already running, re-activated via D-Bus --
/// with a `filetile://open?path=...` deep link. See
/// docs/flutter/ in doc-block for the sending side.
const _openPathChannel = MethodChannel('filetile/open_path');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize path service with home directory
  final homeDir = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];

  if (homeDir != null) {
    await PathService.init(homeDir);
  }

  if (Platform.isLinux) {
    unawaited(ensureRegisteredAsUrlHandler());
  }

  final viewModel = DesktopViewModel();
  _openPathChannel.setMethodCallHandler((call) async {
    if (call.method != 'openPath') return;
    final path = call.arguments as String;
    await _waitUntilInitialized(viewModel);
    await viewModel.loadDirectory(path);
  });

  runApp(MyApp(viewModel: viewModel));
}

/// Waits for [viewModel]'s async startup (reading config, loading the last
/// directory) to finish, so a deep link that arrives during a cold start
/// doesn't get dropped by [DesktopViewModel.loadDirectory]'s init guard.
Future<void> _waitUntilInitialized(DesktopViewModel viewModel) {
  if (viewModel.isInitialized) return Future.value();
  final completer = Completer<void>();
  void listener() {
    if (viewModel.isInitialized) {
      viewModel.removeListener(listener);
      completer.complete();
    }
  }

  viewModel.addListener(listener);
  return completer.future;
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key, required this.viewModel}) : super(key: key);

  final DesktopViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewModel,
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
