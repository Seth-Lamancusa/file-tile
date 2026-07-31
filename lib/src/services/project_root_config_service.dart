import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'path_service.dart';

/// Service for reading and writing desktop view configuration.
/// Stores configuration as JSON in the project root directory.
class ProjectRootConfigService {
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

  /// Write configuration to disk.
  static Future<void> writeLocalConfig(Map<String, dynamic> config) async {
    try {
      await PathService.ensureDirsExist();
      final file = File(PathService.localConfigPath);
      await file.writeAsString(jsonEncode(config));
    } catch (e) {
      debugPrint('Error writing config: $e');
    }
  }
}
