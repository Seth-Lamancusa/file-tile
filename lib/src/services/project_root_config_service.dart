import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'path_service.dart';

/// Simple async lock to prevent concurrent file writes.
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

/// Service for reading and writing desktop view configuration.
/// Stores configuration as JSON in the project root directory.
class ProjectRootConfigService {
  static final _writeLock = _AsyncLock();
  /// Read the local configuration from disk.
  /// Returns an empty map if the file doesn't exist.
  static Future<Map<String, dynamic>> readLocalConfig() async {
    try {
      final file = File(PathService.localConfigPath);
      if (!await file.exists()) {
        return {};
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return {};
      }
      final data = jsonDecode(content);
      return Map<String, dynamic>.from(data ?? {});
    } catch (e) {
      debugPrint('Error reading config: $e');
      return {};
    }
  }

  /// Write configuration to disk with a lock to prevent concurrent writes.
  static Future<void> writeLocalConfig(Map<String, dynamic> config) async {
    await _writeLock.acquire();
    try {
      await PathService.ensureDirsExist();
      final file = File(PathService.localConfigPath);
      await file.writeAsString(jsonEncode(config));
    } catch (e) {
      debugPrint('Error writing config: $e');
    } finally {
      _writeLock.release();
    }
  }

  /// Atomically read, modify, and write config under a lock.
  /// The callback receives the current config and should return the modified config.
  static Future<void> updateLocalConfig(
    Map<String, dynamic> Function(Map<String, dynamic>) updateFn,
  ) async {
    await _writeLock.acquire();
    try {
      await PathService.ensureDirsExist();
      final file = File(PathService.localConfigPath);
      final currentConfig = await readLocalConfig();
      final updatedConfig = updateFn(currentConfig);
      await file.writeAsString(jsonEncode(updatedConfig));
    } catch (e) {
      debugPrint('Error updating config: $e');
    } finally {
      _writeLock.release();
    }
  }
}
