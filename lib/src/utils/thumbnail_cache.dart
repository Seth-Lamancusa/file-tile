import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

const int kThumbnailTargetPx = 128;
const int kThumbnailMaxBytes = 20 * 1024 * 1024;
const int kThumbnailCacheLimit = 48;
const int kThumbnailMaxConcurrent = 3;

class ThumbFilePayload {
  final Uint8List bytes;
  final int mtimeMs;

  const ThumbFilePayload({required this.bytes, required this.mtimeMs});
}

/// Reads image bytes off the UI isolate. Decode uses the engine codec
/// (already off the UI thread) with [targetWidth].
ThumbFilePayload? readThumbFileSync(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final stat = file.statSync();
  if (stat.type != FileSystemEntityType.file) return null;
  if (stat.size <= 0 || stat.size > kThumbnailMaxBytes) return null;
  return ThumbFilePayload(
    bytes: file.readAsBytesSync(),
    mtimeMs: stat.modified.millisecondsSinceEpoch,
  );
}

typedef ThumbFileLoader = Future<ThumbFilePayload?> Function(String path);

Future<ThumbFilePayload?> loadThumbFile(String path) {
  return Isolate.run(() => readThumbFileSync(path));
}

class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache({
    ThumbFileLoader? loader,
    this.maxEntries = kThumbnailCacheLimit,
    this.maxConcurrent = kThumbnailMaxConcurrent,
  }) : _loader = loader ?? loadThumbFile;

  final ThumbFileLoader _loader;
  final int maxEntries;
  final int maxConcurrent;

  final Map<String, ui.Image> _images = {};
  final Map<String, int> _mtimes = {};
  final List<String> _lru = [];
  final Set<String> _inFlight = {};
  final List<String> _queue = [];
  Set<String> _visible = {};
  Set<String> _decode = {};
  bool _disposed = false;
  bool _notifyScheduled = false;
  int _active = 0;

  ui.Image? imageFor(String path) => _images[path];

  /// [visible] images are never evicted (so zoom-out cannot flash them to
  /// icons). [decode] is the subset that should be loaded if missing; omit it
  /// to decode everything in [visible].
  void setVisible(Set<String> visible, {Set<String>? decode}) {
    if (_disposed) return;
    final nextDecode = decode ?? visible;
    final sameVisible = setEquals(_visible, visible);
    final sameDecode = setEquals(_decode, nextDecode);
    if (sameVisible && sameDecode) return;

    _visible = Set.of(visible);
    _decode = Set.of(nextDecode);
    _queue.removeWhere((path) => !_decode.contains(path));
    for (final path in _decode) {
      _enqueue(path);
    }
    _evictIfNeeded();
    _pump();
  }

  void _enqueue(String path) {
    if (_images.containsKey(path) ||
        _inFlight.contains(path) ||
        _queue.contains(path)) {
      if (_images.containsKey(path)) _touch(path);
      return;
    }
    _queue.add(path);
  }

  void _pump() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final path = _queue.removeAt(0);
      if (_images.containsKey(path) || !_decode.contains(path)) continue;
      unawaited(_load(path));
    }
  }

  Future<void> _load(String path) async {
    if (_disposed) return;
    _inFlight.add(path);
    _active++;
    try {
      final payload = await _loader(path);
      if (_disposed) return;
      if (payload == null) {
        _remove(path);
        return;
      }
      final codec = await ui.instantiateImageCodec(
        payload.bytes,
        targetWidth: kThumbnailTargetPx,
      );
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _images.remove(path)?.dispose();
      _images[path] = frame.image;
      _mtimes[path] = payload.mtimeMs;
      _touch(path);
      _evictIfNeeded();
      _scheduleNotify();
    } catch (e) {
      debugPrint('Thumbnail failed for $path: $e');
    } finally {
      _inFlight.remove(path);
      _active--;
      if (!_disposed) _pump();
    }
  }

  void _touch(String path) {
    _lru.remove(path);
    _lru.add(path);
  }

  void _remove(String path) {
    _images.remove(path)?.dispose();
    _mtimes.remove(path);
    _lru.remove(path);
  }

  void _evictIfNeeded() {
    while (_images.length > maxEntries) {
      String? victim;
      for (final path in _lru) {
        if (!_visible.contains(path)) {
          victim = path;
          break;
        }
      }
      // Still on-screen: keep the GPU texture and let the tile scale it.
      if (victim == null) break;
      _remove(victim);
    }
  }

  void _scheduleNotify() {
    if (_disposed || _notifyScheduled) return;
    _notifyScheduled = true;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
    binding.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _mtimes.clear();
    _lru.clear();
    super.dispose();
  }
}
