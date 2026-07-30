import 'dart:io';

/// Simple path service for managing application directories.
/// Stores data in a `.stitch_desktop` directory in the provided base directory.
class PathService {
  static String _baseDir = '';

  /// Initialize with a base directory path.
  /// If not called, defaults to current directory.
  static Future<void> init(String basePath) async {
    _baseDir = basePath;
  }

  /// Get the base directory. Defaults to current directory if not initialized.
  static String get baseDir {
    if (_baseDir.isEmpty) {
      _baseDir = Directory.current.path;
    }
    return _baseDir;
  }

  /// Path to the local config file (.stitch_desktop_config.json)
  static String get localConfigPath {
    return '${baseDir}/.stitch_desktop_config.json';
  }

  /// Ensure the base directory exists.
  static Future<void> ensureDirsExist() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
