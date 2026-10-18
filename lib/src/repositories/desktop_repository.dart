import '../models/directory_layout_issue.dart';
import '../models/metadata_backend.dart';
import '../models/new_element_placement_config.dart';
import '../models/trash_token.dart';

/// A directory entry as seen by [DesktopRepository].
class DesktopEntity {
  final String name;
  final bool isDirectory;
  final bool isSymlink;

  /// Last content modification time. Null when the filesystem did not
  /// report one. Used to order an item's first placement in the inbox.
  final DateTime? modified;

  DesktopEntity({
    required this.name,
    required this.isDirectory,
    this.isSymlink = false,
    this.modified,
  });
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

  /// Create a symbolic link at [path] pointing at [target].
  /// Returns `true` if it was created, `false` if something already
  /// exists at [path]. [target] is stored as given (absolute or relative).
  Future<bool> createSymlink(String path, String target);

  /// Move the file or directory at [path] to the trash.
  ///
  /// Returns a token when the item can be restored with [restore]. Returns
  /// null when the platform removed it but this app cannot put it back.
  /// Throws if nothing exists at [path].
  Future<TrashToken?> delete(String path);

  /// Restore a previously trashed item to [TrashToken.originalPath].
  /// Throws if that path is occupied or the trash entry is gone.
  Future<void> restore(TrashToken token);

  /// Rename/move the file or directory at [oldPath] to [newPath].
  /// No-ops if nothing exists at [oldPath].
  Future<void> rename(String oldPath, String newPath);

  /// Recursively copy a file or directory from [sourcePath] to [destPath].
  /// [destPath] must not already exist.
  Future<void> copyEntry(String sourcePath, String destPath);

  /// Preferred layout backend from `metadata_backend` (default json).
  MetadataBackend get metadataBackend;

  /// Switch layout backend: copy known dirs into the new store, then
  /// best-effort wipe the old store. Failed wipes stay as leftovers.
  Future<void> setMetadataBackend(MetadataBackend backend);

  /// Soft warning from the last layout read/write for [path] (leftover store).
  DirectoryLayoutIssue? takeLayoutWarning(String path);

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
  Future<void> updateNewElementPlacementConfig(
      String path, NewElementPlacementConfig config);
}
