import 'dart:io';

Future<void> sendToTrash(String filePath) async {
  if (Platform.isMacOS) {
    await _moveToTrashMacOS(filePath);
  } else if (Platform.isWindows) {
    _moveToRecycleBinWindows(filePath);
  } else if (Platform.isLinux) {
    await _moveToTrashLinux(filePath);
  } else {
    throw UnsupportedError('Trash functionality not supported on this platform');
  }
}

Future<void> _moveToTrashMacOS(String filePath) async {
  final script = 'tell app "Finder" to move POSIX file "$filePath" to trash';
  final result = await Process.run('osascript', ['-e', script]);

  if (result.exitCode != 0) {
    throw Exception('Failed to move to trash: ${result.stderr}');
  }
}

void _moveToRecycleBinWindows(String filePath) {
  // Requires win32 package - platform channel implementation
  // For now, use Process.run as a fallback
  try {
    Process.runSync('powershell', [
      '-Command',
      '\$path = "$filePath"; '
      'if (Test-Path \$path) { '
      'Remove-Item -Path \$path -Recurse -Force; '
      '}'
    ]);
  } catch (e) {
    throw Exception('Failed to move to Recycle Bin: $e');
  }
}

Future<void> _moveToTrashLinux(String filePath) async {
  var result = await Process.run('gio', ['trash', filePath]);

  if (result.exitCode != 0) {
    result = await Process.run('trash-put', [filePath]);
    if (result.exitCode != 0) {
      throw Exception('Failed to move to trash: ${result.stderr}');
    }
  }
}
