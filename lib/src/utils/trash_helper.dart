import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/trash_token.dart';

/// Move [filePath] to the trash.
///
/// On Linux this follows the FreeDesktop trash spec and returns a token that
/// [restoreFromTrash] can use. Other platforms keep their previous behavior
/// and return null, because those deletes cannot be restored from here.
Future<TrashToken?> sendToTrash(String filePath) async {
  final absolute = p.normalize(File(filePath).absolute.path);
  final type = await FileSystemEntity.type(absolute, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    throw FileSystemException('Path does not exist', absolute);
  }

  if (Platform.isLinux) {
    try {
      return await moveToTrashDirectory(
        absolute,
        trashDirectory: _linuxTrashDirectory(absolute),
      );
    } catch (_) {
      return _gioTrash(absolute);
    }
  } else if (Platform.isMacOS) {
    await _moveToTrashMacOS(absolute);
    return null;
  } else if (Platform.isWindows) {
    _moveToRecycleBinWindows(absolute);
    return null;
  } else {
    throw UnsupportedError('Trash functionality not supported on this platform');
  }
}

/// Move [filePath] into a FreeDesktop trash directory and write its info file.
Future<TrashToken> moveToTrashDirectory(
  String filePath, {
  required String trashDirectory,
}) async {
  final absolute = p.normalize(File(filePath).absolute.path);
  final type = await FileSystemEntity.type(absolute, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    throw FileSystemException('Path does not exist', absolute);
  }

  final filesDir = Directory(p.join(trashDirectory, 'files'));
  final infoDir = Directory(p.join(trashDirectory, 'info'));
  await filesDir.create(recursive: true);
  await infoDir.create(recursive: true);

  final base = _uniqueTrashName(filesDir.path, p.basename(absolute));
  final trashedPath = p.join(filesDir.path, base);
  final infoPath = p.join(infoDir.path, '$base.trashinfo');
  await _renameEntity(absolute, trashedPath);
  try {
    await File(infoPath).writeAsString(
      '[Trash Info]\n'
      'Path=${percentEncodeTrashPath(absolute)}\n'
      'DeletionDate=${_formatTrashDate(DateTime.now())}\n',
    );
  } catch (e) {
    try {
      await _renameEntity(trashedPath, absolute);
    } catch (_) {}
    rethrow;
  }
  return TrashToken(
    originalPath: absolute,
    trashedPath: trashedPath,
    infoPath: infoPath,
  );
}

/// Put a trashed item back at [TrashToken.originalPath].
Future<void> restoreFromTrash(TrashToken token) async {
  final originalType =
      await FileSystemEntity.type(token.originalPath, followLinks: false);
  if (originalType != FileSystemEntityType.notFound) {
    throw FileSystemException('Path already exists', token.originalPath);
  }
  final trashedType =
      await FileSystemEntity.type(token.trashedPath, followLinks: false);
  if (trashedType == FileSystemEntityType.notFound) {
    throw FileSystemException('Trash entry is gone', token.trashedPath);
  }
  final parent = Directory(p.dirname(token.originalPath));
  if (!await parent.exists()) {
    throw FileSystemException('Original directory is gone', token.originalPath);
  }
  await _renameEntity(token.trashedPath, token.originalPath);
  final info = File(token.infoPath);
  if (await info.exists()) {
    await info.delete();
  }
}

/// Percent-encode a trash `Path` value. Slashes stay literal.
String percentEncodeTrashPath(String path) {
  final bytes = utf8.encode(path);
  final buf = StringBuffer();
  for (final b in bytes) {
    final unreserved = (b >= 0x41 && b <= 0x5A) ||
        (b >= 0x61 && b <= 0x7A) ||
        (b >= 0x30 && b <= 0x39) ||
        b == 0x2D ||
        b == 0x5F ||
        b == 0x2E ||
        b == 0x7E ||
        b == 0x2F;
    if (unreserved) {
      buf.writeCharCode(b);
    } else {
      buf.write('%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
  }
  return buf.toString();
}

String percentDecodeTrashPath(String encoded) {
  final bytes = <int>[];
  for (var i = 0; i < encoded.length; i++) {
    if (encoded[i] == '%' && i + 2 < encoded.length) {
      final value = int.tryParse(encoded.substring(i + 1, i + 3), radix: 16);
      if (value != null) {
        bytes.add(value);
        i += 2;
        continue;
      }
    }
    final code = encoded.codeUnitAt(i);
    if (code > 0xFF) {
      bytes.addAll(utf8.encode(encoded[i]));
    } else {
      bytes.add(code);
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _formatTrashDate(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)}'
      'T${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _uniqueTrashName(String filesDir, String base) {
  if (!_exists(p.join(filesDir, base))) return base;
  for (var i = 2; i < 10000; i++) {
    final candidate = '$base.$i';
    if (!_exists(p.join(filesDir, candidate))) return candidate;
  }
  return '$base.${DateTime.now().microsecondsSinceEpoch}';
}

bool _exists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

Future<void> _renameEntity(String from, String to) async {
  final type = await FileSystemEntity.type(from, followLinks: false);
  switch (type) {
    case FileSystemEntityType.directory:
      await Directory(from).rename(to);
    case FileSystemEntityType.link:
      await Link(from).rename(to);
    case FileSystemEntityType.notFound:
      throw FileSystemException('Path does not exist', from);
    default:
      await File(from).rename(to);
  }
}

String _homeTrashDir() {
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) return p.join(xdg, 'Trash');
  final home = Platform.environment['HOME'] ?? '';
  return p.join(home, '.local', 'share', 'Trash');
}

String _linuxTrashDirectory(String absolutePath) {
  final homeTrash = _homeTrashDir();
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return homeTrash;
  final fileMount = _mountPoint(absolutePath);
  final homeMount = _mountPoint(p.normalize(Directory(home).absolute.path));
  if (fileMount == null || homeMount == null || fileMount == homeMount) {
    return homeTrash;
  }
  final uid = _linuxUid();
  final stickyPath = p.join(fileMount, '.Trash', uid);
  if (_exists(stickyPath)) {
    final mode = Directory(stickyPath).statSync().mode;
    // FreeDesktop: $topdir/.Trash/$uid is only used when the sticky bit is set.
    if (mode & 512 != 0) return stickyPath;
  }
  return p.join(fileMount, '.Trash-$uid');
}

String _linuxUid() {
  try {
    final status = File('/proc/self/status').readAsLinesSync();
    for (final line in status) {
      if (!line.startsWith('Uid:')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) return parts[1];
    }
  } catch (_) {}
  return '0';
}

String? _mountPoint(String absolutePath) {
  final File mountInfo = File('/proc/self/mountinfo');
  if (!mountInfo.existsSync()) return null;
  String? best;
  var bestLen = -1;
  for (final line in mountInfo.readAsLinesSync()) {
    final sep = line.indexOf(' - ');
    final head = sep == -1 ? line : line.substring(0, sep);
    final fields = head.split(' ');
    if (fields.length < 5) continue;
    var mount = fields[4].replaceAll(r'\040', ' ');
    if (mount.length > 1) {
      mount = mount.replaceAll(RegExp(r'/+$'), '');
    }
    final matches = absolutePath == mount ||
        mount == '/' ||
        absolutePath.startsWith('$mount/');
    if (matches && mount.length > bestLen) {
      best = mount;
      bestLen = mount.length;
    }
  }
  return best;
}

Future<TrashToken?> _gioTrash(String absolute) async {
  final before = _trashInfoPaths(absolute);
  var result = await Process.run('gio', ['trash', absolute]);
  if (result.exitCode != 0) {
    result = await Process.run('trash-put', [absolute]);
    if (result.exitCode != 0) {
      throw Exception('Failed to move to trash: ${result.stderr}');
    }
  }
  final fresh = _trashInfoPaths(absolute).difference(before);
  for (final infoPath in fresh) {
    final token = _tokenFromInfo(infoPath, absolute);
    if (token != null) return token;
  }
  return null;
}

Set<String> _trashInfoPaths(String absolute) {
  final dirs = <String>[
    p.join(_homeTrashDir(), 'info'),
    p.join(_linuxTrashDirectory(absolute), 'info'),
  ];
  final paths = <String>{};
  for (final dir in dirs) {
    final info = Directory(dir);
    if (!info.existsSync()) continue;
    for (final entity in info.listSync(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.trashinfo')) {
        paths.add(entity.path);
      }
    }
  }
  return paths;
}

TrashToken? _tokenFromInfo(String infoPath, String expectedPath) {
  final text = File(infoPath).readAsStringSync();
  String? path;
  for (final line in LineSplitter.split(text)) {
    if (line.startsWith('Path=')) {
      path = percentDecodeTrashPath(line.substring(5).trim());
    }
  }
  if (path != expectedPath) return null;
  final fileName = p.basename(infoPath);
  const suffix = '.trashinfo';
  if (!fileName.endsWith(suffix)) return null;
  final base = fileName.substring(0, fileName.length - suffix.length);
  return TrashToken(
    originalPath: expectedPath,
    trashedPath: p.join(p.dirname(p.dirname(infoPath)), 'files', base),
    infoPath: infoPath,
  );
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
