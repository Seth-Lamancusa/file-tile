import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_tile/src/utils/thumbnail_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _tinyPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes visible images and skips missing files', () async {
    final png = await _tinyPng();
    final cache = ThumbnailCache(
      loader: (path) async {
        if (path == '/missing.png') return null;
        return ThumbFilePayload(bytes: png, mtimeMs: 1);
      },
    );

    cache.setVisible({'/a.png'});
    await _pumpUntil(() => cache.imageFor('/a.png') != null);

    expect(cache.imageFor('/a.png'), isA<ui.Image>());
    expect(cache.imageFor('/missing.png'), isNull);

    cache.dispose();
  });

  test('evicts non-visible entries when over the cache limit', () async {
    final png = await _tinyPng();
    final cache = ThumbnailCache(
      maxEntries: 1,
      loader: (path) async => ThumbFilePayload(bytes: png, mtimeMs: 1),
    );

    cache.setVisible({'/a.png'});
    await _pumpUntil(() => cache.imageFor('/a.png') != null);

    cache.setVisible({'/b.png'});
    await _pumpUntil(() => cache.imageFor('/b.png') != null);

    expect(cache.imageFor('/a.png'), isNull);
    expect(cache.imageFor('/b.png'), isNotNull);
    cache.dispose();
  });

  test('does not evict images that are still visible', () async {
    final png = await _tinyPng();
    final cache = ThumbnailCache(
      maxEntries: 1,
      loader: (path) async => ThumbFilePayload(bytes: png, mtimeMs: 1),
    );

    cache.setVisible({'/a.png', '/b.png'});
    await _pumpUntil(() =>
        cache.imageFor('/a.png') != null && cache.imageFor('/b.png') != null);

    expect(cache.imageFor('/a.png'), isNotNull);
    expect(cache.imageFor('/b.png'), isNotNull);
    cache.dispose();
  });

  test('keeps a cached thumb when it is visible but not queued to decode',
      () async {
    final png = await _tinyPng();
    final cache = ThumbnailCache(
      maxEntries: 1,
      loader: (path) async => ThumbFilePayload(bytes: png, mtimeMs: 1),
    );

    cache.setVisible({'/a.png'});
    await _pumpUntil(() => cache.imageFor('/a.png') != null);

    cache.setVisible({'/a.png'}, decode: {});
    expect(cache.imageFor('/a.png'), isNotNull);
    cache.dispose();
  });
}

Future<void> _pumpUntil(bool Function() condition,
    {Duration timeout = const Duration(seconds: 3)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
