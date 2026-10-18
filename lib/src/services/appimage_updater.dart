import 'dart:io';

/// What `appimageupdatetool --check-for-update` reported.
///
/// The tool's own exit codes are the opposite of a casual reading of "0 means
/// yes": 0 is up to date, 1 means an update is available, and any other code
/// is an error (including "this AppImage has no update information").
enum AppImageUpdateStatus { updateAvailable, upToDate, unavailable }

class AppImageInstallResult {
  const AppImageInstallResult.installed()
      : installed = true,
        message = '';

  const AppImageInstallResult.failed(this.message) : installed = false;

  final bool installed;
  final String message;
}

typedef AppImageProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
  Map<String, String> environment,
);

/// Runs the bundled headless `appimageupdatetool` against `$APPIMAGE`.
///
/// The tool reads update information embedded in the AppImage at package
/// time, so this class does not know the download host. Outside an AppImage,
/// or when the tool or the update string is missing, checks report
/// [AppImageUpdateStatus.unavailable] and the UI stays quiet.
class AppImageUpdater {
  AppImageUpdater({
    Map<String, String>? environment,
    bool Function(String path)? fileExists,
    AppImageProcessRunner? run,
    Future<void> Function(String executable, Map<String, String> environment)?
        startDetached,
    void Function(int code)? exitProcess,
  })  : _environment = environment ?? Platform.environment,
        _fileExists = fileExists ?? _defaultFileExists,
        _run = run ?? _defaultRun,
        _startDetached = startDetached ?? _defaultStartDetached,
        _exitProcess = exitProcess ?? exit;

  static const toolRelativePath = 'usr/bin/appimageupdatetool';
  static const checkTimeout = Duration(seconds: 30);
  static const installTimeout = Duration(minutes: 15);

  final Map<String, String> _environment;
  final bool Function(String path) _fileExists;
  final AppImageProcessRunner _run;
  final Future<void> Function(
      String executable, Map<String, String> environment) _startDetached;
  final void Function(int code) _exitProcess;

  String? get appImagePath {
    final path = _environment['APPIMAGE'];
    if (path == null || path.isEmpty) return null;
    return path;
  }

  String? get toolPath => bundledUpdaterPath(
        environment: _environment,
        exists: _fileExists,
      );

  Future<AppImageUpdateStatus> checkForUpdate() async {
    final tool = toolPath;
    final appImage = appImagePath;
    if (tool == null || appImage == null) {
      return AppImageUpdateStatus.unavailable;
    }
    try {
      final result = await _run(
        tool,
        ['--check-for-update', appImage],
        _toolEnvironment(),
      ).timeout(checkTimeout);
      return statusFromCheckExitCode(result.exitCode);
    } catch (_) {
      return AppImageUpdateStatus.unavailable;
    }
  }

  Future<AppImageInstallResult> installUpdate() async {
    final tool = toolPath;
    final appImage = appImagePath;
    if (tool == null || appImage == null) {
      return const AppImageInstallResult.failed(
        'This build is not an AppImage with the updater bundled.',
      );
    }
    try {
      final result = await _run(
        tool,
        ['--overwrite', appImage],
        _toolEnvironment(),
      ).timeout(installTimeout);
      if (result.exitCode == 0) {
        return const AppImageInstallResult.installed();
      }
      return AppImageInstallResult.failed(
        summarizeToolError(result.stderr?.toString(), result.exitCode),
      );
    } catch (e) {
      return AppImageInstallResult.failed('$e');
    }
  }

  /// Starts the updated AppImage and ends this process.
  Future<void> relaunch() async {
    final appImage = appImagePath;
    if (appImage == null) {
      throw StateError('APPIMAGE is not set');
    }
    await _startDetached(appImage, environmentForRelaunch(_environment));
    _exitProcess(0);
  }

  Map<String, String> _toolEnvironment() {
    return {
      'APPIMAGE_EXTRACT_AND_RUN': '1',
      'LD_LIBRARY_PATH': '',
    };
  }
}

/// `$APPDIR/usr/bin/appimageupdatetool` when that file is present.
String? bundledUpdaterPath({
  required Map<String, String> environment,
  required bool Function(String path) exists,
}) {
  final appDir = environment['APPDIR'];
  if (appDir == null || appDir.isEmpty) return null;
  final separator = appDir.endsWith('/') ? '' : '/';
  final path = '$appDir$separator${AppImageUpdater.toolRelativePath}';
  if (!exists(path)) return null;
  return path;
}

AppImageUpdateStatus statusFromCheckExitCode(int exitCode) {
  switch (exitCode) {
    case 0:
      return AppImageUpdateStatus.upToDate;
    case 1:
      return AppImageUpdateStatus.updateAvailable;
    default:
      return AppImageUpdateStatus.unavailable;
  }
}

/// Environment for the replacement process. The AppImage runtime sets these
/// itself; inheriting the running mount's values breaks the new process.
Map<String, String> environmentForRelaunch(Map<String, String> source) {
  const drop = {
    'LD_LIBRARY_PATH',
    'APPDIR',
    'ARGV0',
    'APPIMAGE',
    'OWD',
  };
  return Map<String, String>.from(source)
    ..removeWhere((key, _) => drop.contains(key));
}

String summarizeToolError(String? stderr, int exitCode) {
  final text = (stderr ?? '').trim();
  if (text.isEmpty) return 'The updater exited with code $exitCode.';
  final lines =
      text.split('\n').where((line) => line.trim().isNotEmpty).toList();
  final tail = lines.length <= 4 ? lines : lines.sublist(lines.length - 4);
  final joined = tail.join('\n');
  if (joined.length <= 400) return joined;
  return joined.substring(joined.length - 400);
}

bool _defaultFileExists(String path) => File(path).existsSync();

Future<ProcessResult> _defaultRun(
  String executable,
  List<String> arguments,
  Map<String, String> environment,
) {
  return Process.run(executable, arguments, environment: environment);
}

Future<void> _defaultStartDetached(
  String executable,
  Map<String, String> environment,
) async {
  await Process.start(
    executable,
    const [],
    mode: ProcessStartMode.detached,
    environment: environment,
  );
}
