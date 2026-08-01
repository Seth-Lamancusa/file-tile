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
  Future<Map<String, dynamic>> loadData() async {
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
      final current = await loadData();
      final updated = updateFn(current);
      await _writeLocked(updated);
      return updated;
    } finally {
      lock.release();
    }
  }

  Future<void> _writeLocked(Map<String, dynamic> data) async {
    try {
      validateAndLoad(json.encode(data));
      await file.parent.create(recursive: true);
      final existedBefore = await file.exists();
      await file.writeAsString(json.encode(data));
      if (!existedBefore) {
        debugPrint('[JsonFileManager] created ${file.path}');
      }
    } catch (e) {
      debugPrint('Error saving ${file.path}: $e');
      rethrow;
    }
  }

  /// Override in subclasses to provide default data structure.
  Map<String, dynamic> getDefaultData() => {};
}
