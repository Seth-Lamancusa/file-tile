import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class _AsyncLock {
  Completer<void>? _completer;

  Future<void> acquire() async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer();
  }

  void release() {
    _completer?.complete();
    _completer = null;
  }
}

abstract class JsonFileManager {
  final File file;
  static final _locks = <String, _AsyncLock>{};

  JsonFileManager(this.file);

  static _AsyncLock _getLock(String path) {
    return _locks.putIfAbsent(path, () => _AsyncLock());
  }

  /// Validate and parse JSON string. Override in subclasses for custom validation.
  Map<String, dynamic> validateAndLoad(String jsonString);

  /// Load data from file with validation. Returns the loaded/default data.
  /// Shares the same per-file lock as [save]/[updateAtomic], so a read can
  /// never observe a write that's only partially applied.
  Future<Map<String, dynamic>> loadData() async {
    final lock = _getLock(file.path);
    await lock.acquire();
    try {
      return await _loadUnlocked();
    } finally {
      lock.release();
    }
  }

  Future<Map<String, dynamic>> _loadUnlocked() async {
    if (!await file.exists()) {
      return getDefaultData();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return getDefaultData();
      }
      return validateAndLoad(content);
    } catch (e) {
      debugPrint('Error loading ${file.path}: $e');
      rethrow;
    }
  }

  /// Save data to file with validation and locking.
  Future<void> save(Map<String, dynamic> data) async {
    final lock = _getLock(file.path);
    await lock.acquire();
    try {
      await _writeLocked(data);
    } finally {
      lock.release();
    }
  }

  /// Atomically read-modify-write the file: loads the current on-disk state,
  /// applies [updateFn], and writes the result, all under a single lock so
  /// concurrent callers (e.g. rapid setting toggles and view-state saves)
  /// can't interleave and silently drop each other's writes.
  Future<Map<String, dynamic>> updateAtomic(
    Map<String, dynamic> Function(Map<String, dynamic>) updateFn,
  ) async {
    final lock = _getLock(file.path);
    await lock.acquire();
    try {
      final current = await _loadUnlocked();
      final updated = updateFn(current);
      await _writeLocked(updated);
      return updated;
    } finally {
      lock.release();
    }
  }

  /// Writes via a temp file + rename so a reader (even one bypassing the
  /// lock, e.g. an external process) never observes a partially-written file.
  Future<void> _writeLocked(Map<String, dynamic> data) async {
    try {
      validateAndLoad(json.encode(data));
      await file.parent.create(recursive: true);
      final existedBefore = await file.exists();
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(json.encode(data));
      await tmpFile.rename(file.path);
      if (!existedBefore) {
        debugPrint('[JsonFileManager] created ${file.path}');
      }
    } catch (e) {
      debugPrint('Error saving ${file.path}: $e');
      rethrow;
    }
  }

  /// Creates the file with default data if it doesn't already exist on disk.
  /// Never touches existing content, so it's safe to call alongside
  /// concurrent readers/writers without clobbering their changes.
  Future<void> ensureExists() async {
    final lock = _getLock(file.path);
    await lock.acquire();
    try {
      if (!await file.exists()) {
        await _writeLocked(getDefaultData());
      }
    } finally {
      lock.release();
    }
  }

  /// Override in subclasses to provide default data structure.
  Map<String, dynamic> getDefaultData() => {};
}
