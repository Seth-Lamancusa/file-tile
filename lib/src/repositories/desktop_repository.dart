import '../models/new_element_placement_config.dart';

/// A directory entry as seen by [DesktopRepository].
class DesktopEntity {
  final String name;
  final bool isDirectory;
  final bool isSymlink;

  DesktopEntity({required this.name, required this.isDirectory, this.isSymlink = false});
}

/// Abstraction over the filesystem access `DesktopViewModel` needs.
///
/// Gives the ViewModel a seam to fake the filesystem in tests and a single
/// place where storage details (config file location, metadata file format)
/// live, instead of talking to `dart:io` and static singletons directly.
abstract class DesktopRepository {
  /// The directory the app should open on startup.
  String get initialDirectory;

  Future<bool> directoryExists(String path);

  /// List the entries directly inside [path].
  Future<List<DesktopEntity>> listEntities(String path);

  /// Create an empty file at [path]. Returns `true` if it was created,
  /// `false` if a file already existed there.
  Future<bool> createFile(String path);

  /// Create a directory at [path]. Returns `true` if it was created,
  /// `false` if it already existed.
  Future<bool> createDirectory(String path);

  /// Delete the file or directory at [path] (directories are removed
  /// recursively). Throws if nothing exists at [path].
  Future<void> delete(String path);

  /// Rename/move the file or directory at [oldPath] to [newPath].
  /// No-ops if nothing exists at [oldPath].
  Future<void> rename(String oldPath, String newPath);

  /// Read the app-wide config. Returns an empty map if none exists yet.
  Future<Map<String, dynamic>> readConfig();

  Future<void> writeConfig(Map<String, dynamic> config);

  /// Atomically read-modify-write the app-wide config.
  Future<void> updateConfig(
    Map<String, dynamic> Function(Map<String, dynamic>) updateFn,
  );

  /// Creates the metadata file for [path] with default content if it doesn't
  /// already exist. Never overwrites existing content.
  Future<void> ensureLayoutFileExists(String path);

  /// Read the saved node layout (position/color per entry name) for the
  /// directory at [path]. Returns an empty map if none exists yet.
  Future<Map<String, dynamic>> readLayout(String path);

  /// Overwrite the saved node layout for the directory at [path].
  Future<void> updateLayout(String path, Map<String, dynamic> layout);

  /// Atomically remove [name]'s entry from the saved layout for [path].
  Future<void> removeFromLayout(String path, String name);

  /// Atomically rename [oldName]'s entry to [newName] in the saved layout
  /// for [path], if present.
  Future<void> renameInLayout(String path, String oldName, String newName);

  /// Read the new element placement configuration for the directory at [path].
  /// Returns the default configuration if none exists yet.
  Future<NewElementPlacementConfig> readNewElementPlacementConfig(String path);

  /// Update the new element placement configuration for the directory at [path].
  Future<void> updateNewElementPlacementConfig(String path, NewElementPlacementConfig config);
}
