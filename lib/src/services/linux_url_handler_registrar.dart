import 'dart:io';

/// Renders the `.desktop` entry that registers this app as the handler for
/// the `filetile://` URL scheme.
String buildDesktopEntryContent(String execPath) {
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=File Tile\n'
      'Exec="$execPath" %u\n'
      'Terminal=false\n'
      'MimeType=x-scheme-handler/filetile;\n'
      'NoDisplay=true\n';
}

/// Whether [desiredContent] differs from what's currently on disk, i.e.
/// whether a (re)write is needed.
bool needsUpdate(String? existingContent, String desiredContent) {
  return existingContent != desiredContent;
}

/// Registers this app as the OS handler for `filetile://` links on Linux.
///
/// A bare AppImage has no install step to hook into, so this runs on every
/// launch instead. It's cheap when already registered (a file read and a
/// string comparison), and self-heals if the AppImage is moved or renamed,
/// since `$APPIMAGE` is re-resolved each time rather than cached.
///
/// Never throws -- registration failing should not prevent the app from
/// starting.
Future<void> ensureRegisteredAsUrlHandler() async {
  try {
    final homeDir = Platform.environment['HOME'];
    if (homeDir == null) return;

    final execPath =
        Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;
    final desiredContent = buildDesktopEntryContent(execPath);

    final applicationsDir = Directory('$homeDir/.local/share/applications');
    final desktopFile =
        File('${applicationsDir.path}/filetile-url-handler.desktop');

    final existingContent =
        await desktopFile.exists() ? await desktopFile.readAsString() : null;
    if (!needsUpdate(existingContent, desiredContent)) return;

    await applicationsDir.create(recursive: true);
    await desktopFile.writeAsString(desiredContent);

    await Process.run('update-desktop-database', [applicationsDir.path]);
    await Process.run(
        'xdg-mime', ['default', 'filetile-url-handler.desktop', 'x-scheme-handler/filetile']);
  } catch (e) {
    stderr.writeln('Failed to register filetile:// URL handler: $e');
  }
}
