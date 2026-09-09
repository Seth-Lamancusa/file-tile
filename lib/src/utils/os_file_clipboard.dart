import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';

class OsFileClipboardSnapshot {
  final List<String> paths;
  final bool isCut;

  const OsFileClipboardSnapshot({
    required this.paths,
    required this.isCut,
  });
}

/// System clipboard for file paths. In-app copy still works if this no-ops.
abstract class OsFileClipboard {
  Future<void> write(List<String> paths, {required bool isCut});
  Future<OsFileClipboardSnapshot?> read();
  Future<void> clear();
}

class NoOpOsFileClipboard implements OsFileClipboard {
  @override
  Future<void> write(List<String> paths, {required bool isCut}) async {}

  @override
  Future<OsFileClipboardSnapshot?> read() async => null;

  @override
  Future<void> clear() async {}
}

/// Parses GNOME/MATE `x-special/gnome-copied-files` payloads.
OsFileClipboardSnapshot? parseGnomeCopiedFiles(String payload) {
  final lines = payload
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;
  final verb = lines.first.toLowerCase();
  if (verb != 'copy' && verb != 'cut') return null;
  final paths = <String>[];
  for (final line in lines.skip(1)) {
    final path = _fileUriToPath(line);
    if (path != null) paths.add(path);
  }
  if (paths.isEmpty) return null;
  return OsFileClipboardSnapshot(paths: paths, isCut: verb == 'cut');
}

String encodeGnomeCopiedFiles(List<String> paths, {required bool isCut}) {
  final uris = paths.map((path) => Uri.file(path).toString()).join('\n');
  return '${isCut ? 'cut' : 'copy'}\n$uris';
}

/// Parses `text/uri-list` (one `file://` URI per line).
List<String> parseFileUriList(String payload) {
  final paths = <String>[];
  for (final line in payload.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final path = _fileUriToPath(trimmed);
    if (path != null) paths.add(path);
  }
  return paths;
}

String encodeFileUriList(List<String> paths) {
  return paths.map((path) => Uri.file(path).toString()).join('\r\n');
}

String? _fileUriToPath(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.isScheme('file')) return null;
  return uri.toFilePath();
}

final gnomeCopiedFilesFormat = SimpleValueFormat<String>(
  fallback: SimplePlatformCodec<String>(
    formats: [
      'x-special/gnome-copied-files',
      'x-special/mate-copied-files',
    ],
    onDecode: _decodeUtf8,
    onEncode: _encodeUtf8,
  ),
);

final fileUriListFormat = SimpleValueFormat<String>(
  fallback: SimplePlatformCodec<String>(
    formats: ['text/uri-list'],
    onDecode: _decodeUtf8,
    onEncode: _encodeUtf8,
  ),
);

Future<String?> _decodeUtf8(
    PlatformDataProvider provider, PlatformFormat format) async {
  final value = await provider.getData(format);
  if (value is String) return value;
  if (value is List<int>) return utf8.decode(value, allowMalformed: true);
  return null;
}

Object? _encodeUtf8(String value, PlatformFormat format) => utf8.encode(value);

class SuperOsFileClipboard implements OsFileClipboard {
  @override
  Future<void> write(List<String> paths, {required bool isCut}) async {
    if (paths.isEmpty) return;
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final gnome = encodeGnomeCopiedFiles(paths, isCut: isCut);
    final item = DataWriterItem(suggestedName: p.basename(paths.first));
    item.add(gnomeCopiedFilesFormat(gnome));
    item.add(fileUriListFormat(encodeFileUriList(paths)));
    await clipboard.write([item]);
  }

  @override
  Future<OsFileClipboardSnapshot?> read() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    final reader = await clipboard.read();

    if (reader.canProvide(gnomeCopiedFilesFormat)) {
      final raw = await reader.readValue(gnomeCopiedFilesFormat);
      if (raw != null) {
        final parsed = parseGnomeCopiedFiles(raw);
        if (parsed != null) return parsed;
      }
    }

    if (reader.canProvide(fileUriListFormat)) {
      final raw = await reader.readValue(fileUriListFormat);
      if (raw != null) {
        final paths = parseFileUriList(raw);
        if (paths.isNotEmpty) {
          return OsFileClipboardSnapshot(paths: paths, isCut: false);
        }
      }
    }

    final paths = <String>[];
    for (final item in reader.items) {
      if (!item.canProvide(Formats.fileUri)) continue;
      final uri = await item.readValue(Formats.fileUri);
      if (uri != null && uri.isScheme('file')) {
        paths.add(uri.toFilePath());
      }
    }
    if (paths.isEmpty) return null;
    return OsFileClipboardSnapshot(paths: paths, isCut: false);
  }

  @override
  Future<void> clear() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    await clipboard.write([]);
  }
}
