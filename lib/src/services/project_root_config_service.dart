import 'dart:convert';
import 'dart:io';
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

void debugPrint(String message) {
  // Simple debug print implementation
  // In a Flutter context, you can replace this with Flutter's debugPrint
  if (const bool.fromEnvironment('DEBUG')) {
    print('[DEBUG] $message');
  }
}
