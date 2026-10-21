import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'trash_helper.dart';

/// Extra names for files in an outbound drag, taken before another app can
/// unlink them. A move can then be undone even if the destination deleted
/// the original. [discard] drops any copies that were not put back.
class DragOutSnapshot {
  DragOutSnapshot._(this._roots, this._stashFor);

  final List<Directory> _roots;
  final Map<String, String> _stashFor;

  static Future<DragOutSnapshot> capture(
    List<String> paths, {
    String Function(String sourcePath)? scratchDirectoryFor,
  }) async {
    final roots = <String, Directory>{};
    final stashFor = <String, String>{};
    final session = DateTime.now().microsecondsSinceEpoch.toString();
    var index = 0;
    for (final raw in paths) {
      final source = p.normalize(File(raw).absolute.path);
      final type = await FileSystemEntity.type(source, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      final parentPath = scratchDirectoryFor?.call(source) ??
          sameFilesystemScratchDirectory(source);
      final root = roots[parentPath] ??=
          Directory(p.join(parentPath, session));
      if (!await root.exists()) {
        try {
          await _sweepStale(Directory(parentPath));
          await root.create(recursive: true);
        } catch (e) {
          debugPrint('Drag snapshot directory failed: $e');
          continue;
        }
      }
      final dest = p.join(root.path, '$index', p.basename(source));
      await Directory(p.dirname(dest)).create(recursive: true);
      if (await _hardlinkOrCopy(source, dest)) {
        stashFor[source] = dest;
      }
      index++;
    }
    return DragOutSnapshot._(roots.values.toList(), stashFor);
  }

  /// Move the saved copy back to [originalPath]. False when there is no
  /// copy, or the path is already occupied.
  Future<bool> putBack(String originalPath) async {
    final source = p.normalize(File(originalPath).absolute.path);
    final stash = _stashFor[source];
    if (stash == null) return false;
    final current = await FileSystemEntity.type(source, followLinks: false);
    if (current != FileSystemEntityType.notFound) return false;
    final parent = Directory(p.dirname(source));
    if (!await parent.exists()) return false;
    try {
      await _rename(stash, source);
    } catch (e) {
      debugPrint('Drag snapshot restore failed for $source: $e');
      return false;
    }
    _stashFor.remove(source);
    return true;
  }

  Future<void> discard() async {
    _stashFor.clear();
    for (final root in _roots) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } catch (e) {
        debugPrint('Drag snapshot cleanup failed: $e');
      }
    }
    _roots.clear();
  }
}

Future<void> _sweepStale(Directory parent) async {
  if (!await parent.exists()) return;
  final cutoff = DateTime.now().subtract(const Duration(hours: 12));
  await for (final entity in parent.list(followLinks: false)) {
    if (entity is! Directory) continue;
    try {
      final modified = (await entity.stat()).modified;
      if (modified.isBefore(cutoff)) {
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }
}

Future<bool> _hardlinkOrCopy(String from, String to) async {
  final linked = await Process.run('cp', ['-a', '--link', '--', from, to]);
  if (linked.exitCode == 0) return true;
  final copied = await Process.run('cp', ['-a', '--', from, to]);
  if (copied.exitCode != 0) {
    debugPrint('Drag snapshot failed for $from: ${copied.stderr}');
    return false;
  }
  return true;
}

Future<void> _rename(String from, String to) async {
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
