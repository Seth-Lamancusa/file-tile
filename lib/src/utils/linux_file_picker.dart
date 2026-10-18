import 'dart:io';

/// Runs a command and returns its [ProcessResult].
typedef CommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Linux file and folder chooser backed by zenity.
///
/// The dialog is a separate process, so it works without a Flutter plugin
/// linked into the running app.
class LinuxFilePicker {
  LinuxFilePicker({CommandRunner? run}) : _run = run ?? Process.run;

  final CommandRunner _run;

  Future<String?> pickFile({required String initialDirectory}) {
    return _pick(directory: false, initialDirectory: initialDirectory);
  }

  Future<String?> pickDirectory({required String initialDirectory}) {
    return _pick(directory: true, initialDirectory: initialDirectory);
  }

  Future<String?> _pick({
    required bool directory,
    required String initialDirectory,
  }) async {
    final result = await _run('zenity', [
      '--file-selection',
      if (directory) '--directory',
      '--title=${directory ? 'Choose folder' : 'Choose file'}',
      '--filename=${_dialogStart(initialDirectory)}',
    ]);
    if (result.exitCode != 0) return null;
    final path = '${result.stdout}'.trim();
    if (path.isEmpty) return null;
    return path;
  }
}

/// Zenity treats a trailing slash as "start in this directory".
String _dialogStart(String directory) {
  if (directory.isEmpty || directory.endsWith('/')) return directory;
  return '$directory/';
}
