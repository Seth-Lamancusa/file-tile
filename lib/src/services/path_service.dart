import 'dart:io';

/// Simple path service for managing application directories.
/// Stores data in the provided base directory.
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

  /// Name of the local config file, as it appears on disk.
  static const String configFileName = 'file-tile-config.json';

  /// Old name of the local config file, from before the stitch-grid ->
  /// file-tile rebrand. Renamed to [configFileName] in place on first access
  /// so existing users' settings aren't lost.
  static const String legacyConfigFileName = 'stitch-grid-config.json';

  /// Path to the local config file (file-tile-config.json)
  static String get localConfigPath {
    return '${baseDir}/${configFileName}';
  }

  /// Path to the legacy local config file (stitch-grid-config.json)
  static String get legacyConfigPath {
    return '${baseDir}/${legacyConfigFileName}';
  }

  /// Ensure the base directory exists.
  static Future<void> ensureDirsExist() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
