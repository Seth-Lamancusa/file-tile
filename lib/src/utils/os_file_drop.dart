import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'os_file_clipboard.dart';

const fileTileDragLocalKey = 'file_tile_os_drag';
const fileTileDragLocalPathsKey = 'paths';
const fileTileDragLocalAnchorKey = 'anchor';
const fileTileDragLocalCutKey = 'cut';

List<DataFormat> get osFileDropFormats => [
      gnomeCopiedFilesFormat,
      fileUriListFormat,
      Formats.fileUri,
    ];

/// Outbound drag actions. Ctrl is copy-only. Otherwise offer move and copy:
/// GNOME Files can still move, while browsers (Chrome/Drive) only accept copy.
List<DropOperation> osFileDragOutOperations({required bool controlPressed}) {
  if (controlPressed) return [DropOperation.copy];
  return [DropOperation.move, DropOperation.copy];
}

/// Default is move; Ctrl requests copy. Honor what the source actually allows.
DropOperation preferredOsDropOperation({
  required bool controlPressed,
  required Set<DropOperation> allowed,
}) {
  if (controlPressed && allowed.contains(DropOperation.copy)) {
    return DropOperation.copy;
  }
  if (!controlPressed && allowed.contains(DropOperation.move)) {
    return DropOperation.move;
  }
  if (allowed.contains(DropOperation.copy)) return DropOperation.copy;
  if (allowed.contains(DropOperation.move)) return DropOperation.move;
  return DropOperation.none;
}

bool dropSessionHasFiles(DropSession session) {
  for (final item in session.items) {
    if (isFileTileLocalData(item.localData)) return true;
    if (item.canProvide(Formats.fileUri) ||
        item.canProvide(fileUriListFormat) ||
        item.canProvide(gnomeCopiedFilesFormat)) {
      return true;
    }
    for (final format in item.platformFormats) {
      final lower = format.toLowerCase();
      if (lower.contains('uri-list') ||
          lower.contains('gnome-copied-files') ||
          lower.contains('mate-copied-files')) {
        return true;
      }
    }
  }
  return false;
}

bool isFileTileLocalData(Object? data) {
  return data is Map && data[fileTileDragLocalKey] == true;
}

bool isFileTileLocalDrop(DropSession session) {
  return session.items.any((item) => isFileTileLocalData(item.localData));
}

List<String> fileTileLocalDragPaths(DropSession session) {
  final data = _fileTileLocalData(session);
  if (data == null) return const [];
  final raw = data[fileTileDragLocalPathsKey];
  if (raw is! List) return const [];
  return [for (final path in raw) path.toString()];
}

/// Path of the tile under the pointer when the drag started.
/// Its landing cell is where the OS drag image will sit.
String? fileTileLocalDragAnchor(DropSession session) {
  final raw = _fileTileLocalData(session)?[fileTileDragLocalAnchorKey];
  if (raw is! String || raw.isEmpty) return null;
  return raw;
}

/// Cut/copy frozen into the local payload at drag start.
/// Null for drags that did not start inside File Tile.
bool? fileTileLocalDragIsCut(DropSession session) {
  final raw = _fileTileLocalData(session)?[fileTileDragLocalCutKey];
  if (raw is bool) return raw;
  return null;
}

Map<dynamic, dynamic>? _fileTileLocalData(DropSession session) {
  for (final item in session.items) {
    final data = item.localData;
    if (isFileTileLocalData(data) && data is Map) return data;
  }
  return null;
}

/// True when [destDir] is one of [sourcePaths] or nested inside one of them.
bool isDropIntoSelf(String destDir, List<String> sourcePaths) {
  for (final source in sourcePaths) {
    if (destDir == source || p.isWithin(source, destDir)) return true;
  }
  return false;
}

Future<OsFileClipboardSnapshot?> readDropSession(
  DropSession session, {
  required bool defaultCut,
}) async {
  for (final item in session.items) {
    final reader = item.dataReader;
    if (reader == null) continue;
    if (reader.canProvide(gnomeCopiedFilesFormat)) {
      final raw = await _readDropValue(reader, gnomeCopiedFilesFormat);
      if (raw != null) {
        final parsed = parseGnomeCopiedFiles(raw);
        if (parsed != null) return parsed;
      }
    }
  }

  for (final item in session.items) {
    final reader = item.dataReader;
    if (reader == null) continue;
    if (reader.canProvide(fileUriListFormat)) {
      final raw = await _readDropValue(reader, fileUriListFormat);
      if (raw != null) {
        final paths = parseFileUriList(raw);
        if (paths.isNotEmpty) {
          return OsFileClipboardSnapshot(paths: paths, isCut: defaultCut);
        }
      }
    }
  }

  final paths = <String>[];
  for (final item in session.items) {
    final reader = item.dataReader;
    if (reader == null) continue;
    if (!reader.canProvide(Formats.fileUri)) continue;
    final uri = await _readDropValue(reader, Formats.fileUri);
    if (uri != null && uri.isScheme('file')) {
      paths.add(uri.toFilePath());
    }
  }
  if (paths.isEmpty) return null;
  return OsFileClipboardSnapshot(paths: paths, isCut: defaultCut);
}

Future<T?> _readDropValue<T extends Object>(
    DataReader reader, ValueFormat<T> format) {
  final done = Completer<T?>();
  final progress = reader.getValue<T>(format, (value) {
    if (!done.isCompleted) done.complete(value);
  }, onError: (error) {
    if (!done.isCompleted) done.completeError(error);
  });
  if (progress == null && !done.isCompleted) {
    done.complete(null);
  }
  return done.future;
}
