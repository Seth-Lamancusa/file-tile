import 'package:path/path.dart' as p;
import 'package:file_tile/src/models/new_element_placement_config.dart';
import 'package:file_tile/src/models/directory_layout_issue.dart';
import 'package:file_tile/src/models/metadata_backend.dart';
import 'package:file_tile/src/repositories/desktop_repository.dart';

/// In-memory [DesktopRepository] for tests. No real file I/O.
class FakeDesktopRepository implements DesktopRepository {
  @override
  final String initialDirectory;

  final Set<String> _directories = {};
  final Map<String, List<DesktopEntity>> _children = {};
  final Map<String, Map<String, dynamic>> _layouts = {};
  Map<String, dynamic> _config = {};

  Object? layoutIoError;
  String? layoutIoErrorPath;
  int updateLayoutCount = 0;

  /// When set, [readConfig] throws this instead of returning data.
  Object? readConfigError;
  Map<String, dynamic> get configSnapshot => Map<String, dynamic>.from(_config);

  Object? listEntitiesError;
  String? listEntitiesErrorPath;

  @override
  MetadataBackend metadataBackend = MetadataBackend.json;

  FakeDesktopRepository({this.initialDirectory = '/root'}) {
    _directories.add(initialDirectory);
  }

  /// Test setup helper: declare that [path] is a directory containing
  /// [entities], optionally with a saved [layout].
  void seedDirectory(String path, List<DesktopEntity> entities,
      {Map<String, dynamic>? layout}) {
    _directories.add(path);
    _children[path] = List.of(entities);
    if (layout != null) {
      _layouts[path] = Map<String, dynamic>.from(layout);
    }
  }

  @override
  Future<bool> directoryExists(String path) async =>
      _directories.contains(path);

  @override
  Future<List<DesktopEntity>> listEntities(String path) async {
    if (listEntitiesError != null &&
        (listEntitiesErrorPath == null || listEntitiesErrorPath == path)) {
      throw listEntitiesError!;
    }
    return List.of(_children[path] ?? []);
  }

  @override
  Future<bool> createFile(String path) async {
    final dir = p.dirname(path);
    final name = p.basename(path);
    final list = _children.putIfAbsent(dir, () => []);
    if (list.any((e) => e.name == name)) return false;
    list.add(DesktopEntity(name: name, isDirectory: false));
    return true;
  }

  @override
  Future<bool> createDirectory(String path) async {
    final dir = p.dirname(path);
    final name = p.basename(path);
    final list = _children.putIfAbsent(dir, () => []);
    if (list.any((e) => e.name == name)) return false;
    list.add(DesktopEntity(name: name, isDirectory: true));
    _directories.add(path);
    return true;
  }

  @override
  Future<void> delete(String path) async {
    final dir = p.dirname(path);
    final name = p.basename(path);
    final list = _children[dir];
    if (list == null || !list.any((e) => e.name == name)) {
      throw Exception('Path does not exist: $path');
    }
    list.removeWhere((e) => e.name == name);
    _directories.remove(path);
    _children.remove(path);
    _layouts.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    if (oldPath == newPath) return;
    final oldDir = p.dirname(oldPath);
    final newDir = p.dirname(newPath);
    final oldName = p.basename(oldPath);
    final newName = p.basename(newPath);
    final list = _children[oldDir];
    if (list == null) return;
    final index = list.indexWhere((e) => e.name == oldName);
    if (index == -1) return;
    final old = list.removeAt(index);
    _children.putIfAbsent(newDir, () => []);
    _children[newDir]!.add(DesktopEntity(
      name: newName,
      isDirectory: old.isDirectory,
      isSymlink: old.isSymlink,
    ));
    if (old.isDirectory) {
      _relocateTree(oldPath, newPath, copy: false);
    }
  }

  @override
  Future<void> copyEntry(String sourcePath, String destPath) async {
    final srcDir = p.dirname(sourcePath);
    final destDir = p.dirname(destPath);
    final srcName = p.basename(sourcePath);
    final destName = p.basename(destPath);
    final srcList = _children[srcDir];
    if (srcList == null || !srcList.any((e) => e.name == srcName)) {
      throw Exception('Path does not exist: $sourcePath');
    }
    final entity = srcList.firstWhere((e) => e.name == srcName);
    final destList = _children.putIfAbsent(destDir, () => []);
    if (destList.any((e) => e.name == destName)) {
      throw Exception('Path already exists: $destPath');
    }
    destList.add(DesktopEntity(
      name: destName,
      isDirectory: entity.isDirectory,
      isSymlink: entity.isSymlink,
    ));
    if (entity.isDirectory) {
      _relocateTree(sourcePath, destPath, copy: true);
    }
  }

  void _relocateTree(String from, String to, {required bool copy}) {
    if (copy) {
      _directories.add(to);
    } else {
      _directories.remove(from);
      _directories.add(to);
    }
    final kids = copy ? _children[from] : _children.remove(from);
    if (kids == null) {
      _children.putIfAbsent(to, () => []);
      return;
    }
    _children[to] = [
      for (final e in kids)
        DesktopEntity(
          name: e.name,
          isDirectory: e.isDirectory,
          isSymlink: e.isSymlink,
        )
    ];
    for (final e in kids) {
      if (e.isDirectory) {
        _relocateTree(p.join(from, e.name), p.join(to, e.name), copy: copy);
      }
    }
    if (!copy && _layouts.containsKey(from)) {
      _layouts[to] = _layouts.remove(from)!;
    }
  }

  @override
  Future<Map<String, dynamic>> readConfig() async {
    if (readConfigError != null) throw readConfigError!;
    return Map<String, dynamic>.from(_config);
  }

  @override
  Future<void> writeConfig(Map<String, dynamic> config) async {
    _config = Map<String, dynamic>.from(config);
  }

  @override
  Future<void> updateConfig(
    Map<String, dynamic> Function(Map<String, dynamic>) updateFn,
  ) async {
    _config = updateFn(Map<String, dynamic>.from(_config));
  }

  @override
  Future<void> setMetadataBackend(MetadataBackend backend) async {
    metadataBackend = backend;
    _config[MetadataBackend.configKey] = backend.configValue;
  }

  @override
  DirectoryLayoutIssue? takeLayoutWarning(String path) => null;

  void _throwIfLayoutError(String path) {
    if (layoutIoError == null) return;
    if (layoutIoErrorPath != null && layoutIoErrorPath != path) return;
    throw layoutIoError!;
  }

  @override
  Future<void> ensureLayoutFileExists(String path) async {
    _throwIfLayoutError(path);
    _layouts.putIfAbsent(path, () => {});
  }

  @override
  Future<Map<String, dynamic>> readLayout(String path) async {
    _throwIfLayoutError(path);
    return Map<String, dynamic>.from(_layouts[path] ?? {});
  }

  @override
  Future<void> updateLayout(String path, Map<String, dynamic> layout) async {
    _throwIfLayoutError(path);
    updateLayoutCount++;
    _layouts[path] = Map<String, dynamic>.from(layout);
  }

  @override
  Future<void> removeFromLayout(String path, String name) async {
    _throwIfLayoutError(path);
    _layouts[path]?.remove(name);
  }

  @override
  Future<void> renameInLayout(
      String path, String oldName, String newName) async {
    _throwIfLayoutError(path);
    final layout = _layouts[path];
    if (layout != null && layout.containsKey(oldName)) {
      layout[newName] = layout.remove(oldName);
    }
  }

  @override
  Future<NewElementPlacementConfig> readNewElementPlacementConfig(
      String path) async {
    _throwIfLayoutError(path);
    return NewElementPlacementConfig.defaultConfig();
  }

  @override
  Future<void> updateNewElementPlacementConfig(
      String path, NewElementPlacementConfig config) async {
    // No-op for fake repository
  }
}
