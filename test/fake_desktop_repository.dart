import 'package:path/path.dart' as p;
import 'package:stitch_desktop_grid/src/models/new_element_placement_config.dart';
import 'package:stitch_desktop_grid/src/repositories/desktop_repository.dart';

/// In-memory [DesktopRepository] for tests. No real file I/O.
class FakeDesktopRepository implements DesktopRepository {
  @override
  final String initialDirectory;

  final Set<String> _directories = {};
  final Map<String, List<DesktopEntity>> _children = {};
  final Map<String, Map<String, dynamic>> _layouts = {};
  Map<String, dynamic> _config = {};

  /// When set, [readConfig] throws this instead of returning data.
  Object? readConfigError;

  /// Synchronous snapshot of the current config, for test assertions.
  Map<String, dynamic> get configSnapshot => Map<String, dynamic>.from(_config);

  FakeDesktopRepository({this.initialDirectory = '/root'}) {
    _directories.add(initialDirectory);
  }

  /// Test setup helper: declare that [path] is a directory containing
  /// [entities], optionally with a saved [layout].
  void seedDirectory(String path, List<DesktopEntity> entities, {Map<String, dynamic>? layout}) {
    _directories.add(path);
    _children[path] = List.of(entities);
    if (layout != null) {
      _layouts[path] = Map<String, dynamic>.from(layout);
    }
  }

  @override
  Future<bool> directoryExists(String path) async => _directories.contains(path);

  @override
  Future<List<DesktopEntity>> listEntities(String path) async => List.of(_children[path] ?? []);

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
    final dir = p.dirname(oldPath);
    final oldName = p.basename(oldPath);
    final newName = p.basename(newPath);
    final list = _children[dir];
    if (list == null) return;
    final index = list.indexWhere((e) => e.name == oldName);
    if (index == -1) return;
    final old = list[index];
    list[index] = DesktopEntity(name: newName, isDirectory: old.isDirectory);
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
  Future<void> ensureLayoutFileExists(String path) async {
    _layouts.putIfAbsent(path, () => {});
  }

  @override
  Future<Map<String, dynamic>> readLayout(String path) async {
    return Map<String, dynamic>.from(_layouts[path] ?? {});
  }

  @override
  Future<void> updateLayout(String path, Map<String, dynamic> layout) async {
    _layouts[path] = Map<String, dynamic>.from(layout);
  }

  @override
  Future<void> removeFromLayout(String path, String name) async {
    _layouts[path]?.remove(name);
  }

  @override
  Future<void> renameInLayout(String path, String oldName, String newName) async {
    final layout = _layouts[path];
    if (layout != null && layout.containsKey(oldName)) {
      layout[newName] = layout.remove(oldName);
    }
  }

  @override
  Future<NewElementPlacementConfig> readNewElementPlacementConfig(String path) async {
    return NewElementPlacementConfig.defaultConfig();
  }

  @override
  Future<void> updateNewElementPlacementConfig(String path, NewElementPlacementConfig config) async {
    // No-op for fake repository
  }
}
