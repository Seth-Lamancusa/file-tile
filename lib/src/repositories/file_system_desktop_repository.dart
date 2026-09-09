import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/directory_layout_issue.dart';
import '../models/metadata_backend.dart';
import '../models/new_element_placement_config.dart';
import '../services/path_service.dart';
import '../storage/json_layout_store.dart';
import '../storage/layout_database.dart';
import '../storage/sqlite_layout_store.dart';
import '../utils/config_manager.dart';
import '../utils/layout_directory_key.dart';
import '../utils/trash_helper.dart';
import 'desktop_repository.dart';

/// [DesktopRepository] implementation backed by the real filesystem.
///
/// Mostly wraps the existing `PathService`/`ConfigManager`/`MetadataManager`
/// logic that used to be called directly from `DesktopViewModel`.
class FileSystemDesktopRepository implements DesktopRepository {
  FileSystemDesktopRepository({
    LayoutDatabase? layoutDatabase,
    File? sqliteFile,
  })  : _injectedDatabase = layoutDatabase,
        _sqliteFile = sqliteFile;

  ConfigManager? _configManager;
  final LayoutDatabase? _injectedDatabase;
  final File? _sqliteFile;
  LayoutDatabase? _openedDb;
  SqliteLayoutStore? _sqliteStore;
  final JsonLayoutStore _json = JsonLayoutStore();
  MetadataBackend _backend = MetadataBackend.json;
  bool _backendLoaded = false;
  final Map<String, DirectoryLayoutIssue> _layoutWarnings = {};

  static String defaultSqlitePath() =>
      p.join(PathService.baseDir, 'file-tile-layout.sqlite');

  ConfigManager _getConfigManager() {
    return _configManager ??= ConfigManager(
      File(PathService.localConfigPath),
      legacyFile: File(PathService.legacyConfigPath),
    );
  }

  Future<void> _ensureConfigDirExists() async {
    final manager = _getConfigManager();
    if (!await manager.file.exists()) {
      await PathService.ensureDirsExist();
    }
  }

  File get _sqliteDbFile =>
      _sqliteFile ?? File(FileSystemDesktopRepository.defaultSqlitePath());

  Future<MetadataBackend> _preferredBackend() async {
    if (_backendLoaded) return _backend;
    final config = await readConfig();
    _backend = MetadataBackend.fromConfig(config[MetadataBackend.configKey]);
    _backendLoaded = true;
    return _backend;
  }

  Future<SqliteLayoutStore?> _maybeSqlite() async {
    if (_injectedDatabase != null) {
      return _sqliteStore ??= SqliteLayoutStore(_injectedDatabase!);
    }
    if (_sqliteStore != null) return _sqliteStore;
    final file = _sqliteDbFile;
    if (!await file.exists()) return null;
    _openedDb = LayoutDatabase.file(file);
    return _sqliteStore = SqliteLayoutStore(_openedDb!);
  }

  Future<SqliteLayoutStore> _requireSqlite() async {
    final existing = await _maybeSqlite();
    if (existing != null) return existing;
    final file = _sqliteDbFile;
    await file.parent.create(recursive: true);
    _openedDb = LayoutDatabase.file(file);
    return _sqliteStore = SqliteLayoutStore(_openedDb!);
  }

  Future<bool> _sqliteHas(String path) async {
    final store = await _maybeSqlite();
    if (store == null) return false;
    return store.hasDirectory(path);
  }

  Future<void> _sqliteDeleteIfPresent(String path) async {
    final store = await _maybeSqlite();
    if (store == null) return;
    if (!await store.hasDirectory(path)) return;
    await store.deleteDirectory(path);
  }

  Future<void> _importJsonToSqlite(String path) async {
    final bundle = await _json.read(path);
    await (await _requireSqlite()).writeAll(
      path,
      SqliteLayoutBundle(
        layout: bundle.layout,
        placement: bundle.placement,
        version: bundle.version,
      ),
    );
  }

  DirectoryLayoutIssue _fallbackIssue(String path) => DirectoryLayoutIssue(
        path: path,
        kind: DirectoryLayoutIssueKind.storageFallback,
      );

  @override
  String get initialDirectory => PathService.baseDir;

  @override
  MetadataBackend get metadataBackend => _backend;

  @override
  Future<void> setMetadataBackend(MetadataBackend backend) async {
    await _preferredBackend();
    if (_backend == backend) return;
    if (backend == MetadataBackend.sqlite) {
      await _switchToSqlite();
    } else {
      await _switchToJson();
    }
    await updateConfig((config) {
      config[MetadataBackend.configKey] = backend.configValue;
      return config;
    });
    _backend = backend;
    _backendLoaded = true;
    _layoutWarnings.clear();
  }

  Future<Set<String>> _knownDirectoryPaths() async {
    final config = await readConfig();
    final paths = <String>{};
    final last = config['last_visited_directory'] as String?;
    if (last is String && last.isNotEmpty) {
      paths.add(layoutDirectoryKey(last));
    }
    final states = config['desktop_view_states'];
    if (states is Map) {
      for (final key in states.keys) {
        paths.add(layoutDirectoryKey('$key'));
      }
    }
    return paths;
  }

  Future<void> _switchToSqlite() async {
    final paths = await _knownDirectoryPaths();
    final sqlite = await _requireSqlite();
    for (final path in await sqlite.directoryPaths()) {
      paths.add(path);
    }
    for (final path in paths) {
      try {
        if (await _json.exists(path) && !await sqlite.hasDirectory(path)) {
          await _importJsonToSqlite(path);
        }
        if (await sqlite.hasDirectory(path)) {
          await _json.tryDelete(path);
        }
      } catch (_) {
        // Leave JSON in place; do not insert a wiped sqlite default.
      }
    }
  }

  Future<void> _switchToJson() async {
    final store = await _maybeSqlite();
    if (store == null) return;
    for (final path in await store.directoryPaths()) {
      try {
        final bundle = await store.read(path);
        await _json.writeAll(
          path,
          JsonLayoutBundle(
            layout: bundle.layout,
            placement: bundle.placement,
            version: bundle.version,
          ),
        );
        await store.deleteDirectory(path);
      } catch (_) {
        // Keep the sqlite row; leftover fallback will serve this path.
      }
    }
  }

  @override
  DirectoryLayoutIssue? takeLayoutWarning(String path) {
    return _layoutWarnings.remove(layoutDirectoryKey(path));
  }

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<List<DesktopEntity>> listEntities(String path) async {
    final entities = await Directory(path).list(followLinks: false).toList();
    return entities.map((e) {
      bool isDir = e is Directory;
      bool isSymlink = e is Link;

      if (e is Link) {
        final type = FileSystemEntity.typeSync(e.path);
        isDir = type == FileSystemEntityType.directory;
      }

      return DesktopEntity(
        name: p.basename(e.path),
        isDirectory: isDir,
        isSymlink: isSymlink,
      );
    }).toList();
  }

  @override
  Future<bool> createFile(String path) async {
    final file = File(path);
    if (await file.exists()) return false;
    await file.create();
    return true;
  }

  @override
  Future<bool> createDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) return false;
    await dir.create();
    return true;
  }

  @override
  Future<void> delete(String path) async {
    if (await File(path).exists() || await Directory(path).exists()) {
      await sendToTrash(path);
    } else {
      throw FileSystemException('Path does not exist', path);
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    if (await File(oldPath).exists()) {
      await File(oldPath).rename(newPath);
    } else if (await Directory(oldPath).exists()) {
      await Directory(oldPath).rename(newPath);
    }
  }

  @override
  Future<void> copyEntry(String sourcePath, String destPath) async {
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Path does not exist', sourcePath);
    }
    if (type == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(sourcePath), Directory(destPath));
    } else if (type == FileSystemEntityType.link) {
      final target = await Link(sourcePath).target();
      await Link(destPath).create(target);
    } else {
      await File(sourcePath).copy(destPath);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is Link) {
        await Link(newPath).create(await entity.target());
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  @override
  Future<Map<String, dynamic>> readConfig() async {
    final manager = _getConfigManager();
    await manager.load();
    return manager.data;
  }

  @override
  Future<void> writeConfig(Map<String, dynamic> config) async {
    await _ensureConfigDirExists();
    await _getConfigManager().save(config);
  }

  @override
  Future<void> updateConfig(
    Map<String, dynamic> Function(Map<String, dynamic>) updateFn,
  ) async {
    await _ensureConfigDirExists();
    await _getConfigManager().update(updateFn);
  }

  @override
  Future<void> ensureLayoutFileExists(String path) async {
    final key = layoutDirectoryKey(path);
    final preferred = await _preferredBackend();
    if (preferred == MetadataBackend.sqlite) {
      if (await _json.exists(key) && !await _sqliteHas(key)) {
        await _importJsonToSqlite(key);
        await _json.tryDelete(key);
      }
      return;
    }
    if (await _sqliteHas(key) && !await _json.exists(key)) {
      return;
    }
    await _json.ensureExists(key);
  }

  @override
  Future<Map<String, dynamic>> readLayout(String path) async {
    return (await _readBundle(path)).layout;
  }

  @override
  Future<void> updateLayout(String path, Map<String, dynamic> layout) async {
    final key = layoutDirectoryKey(path);
    final preferred = await _preferredBackend();
    if (preferred == MetadataBackend.sqlite) {
      await (await _requireSqlite()).writeLayout(key, layout);
      await _json.tryDelete(key);
      _layoutWarnings.remove(key);
      return;
    }
    if (await _json.exists(key)) {
      try {
        await _json.writeLayout(key, layout);
        await _sqliteDeleteIfPresent(key);
        _layoutWarnings.remove(key);
        return;
      } catch (e) {
        if (await _sqliteHas(key)) {
          await (await _requireSqlite()).writeLayout(key, layout);
          _layoutWarnings[key] = _fallbackIssue(key);
          return;
        }
        rethrow;
      }
    }
    if (await _sqliteHas(key)) {
      final existing = await (await _requireSqlite()).read(key);
      try {
        await _json.writeAll(
          key,
          JsonLayoutBundle(
            layout: layout,
            placement: existing.placement,
            version: existing.version,
          ),
        );
        await _sqliteDeleteIfPresent(key);
        _layoutWarnings.remove(key);
      } catch (_) {
        await (await _requireSqlite()).writeLayout(key, layout);
        _layoutWarnings[key] = _fallbackIssue(key);
      }
      return;
    }
    await _json.writeLayout(key, layout);
    _layoutWarnings.remove(key);
  }

  @override
  Future<void> removeFromLayout(String path, String name) async {
    final key = layoutDirectoryKey(path);
    await _mutate(key, json: () => _json.removeNode(key, name), sqlite: () async {
      await (await _requireSqlite()).removeNode(key, name);
    });
  }

  @override
  Future<void> renameInLayout(
      String path, String oldName, String newName) async {
    final key = layoutDirectoryKey(path);
    await _mutate(key, json: () => _json.renameNode(key, oldName, newName),
        sqlite: () async {
      await (await _requireSqlite()).renameNode(key, oldName, newName);
    });
  }

  @override
  Future<NewElementPlacementConfig> readNewElementPlacementConfig(
      String path) async {
    return (await _readBundle(path)).placement;
  }

  @override
  Future<void> updateNewElementPlacementConfig(
      String path, NewElementPlacementConfig config) async {
    final key = layoutDirectoryKey(path);
    final preferred = await _preferredBackend();
    if (preferred == MetadataBackend.sqlite) {
      await (await _requireSqlite()).writePlacement(key, config);
      await _json.tryDelete(key);
      _layoutWarnings.remove(key);
      return;
    }
    if (await _json.exists(key)) {
      try {
        await _json.writePlacement(key, config);
        await _sqliteDeleteIfPresent(key);
        _layoutWarnings.remove(key);
        return;
      } catch (e) {
        if (await _sqliteHas(key)) {
          await (await _requireSqlite()).writePlacement(key, config);
          _layoutWarnings[key] = _fallbackIssue(key);
          return;
        }
        rethrow;
      }
    }
    if (await _sqliteHas(key)) {
      final existing = await (await _requireSqlite()).read(key);
      try {
        await _json.writeAll(
          key,
          JsonLayoutBundle(
            layout: existing.layout,
            placement: config,
            version: existing.version,
          ),
        );
        await _sqliteDeleteIfPresent(key);
        _layoutWarnings.remove(key);
      } catch (_) {
        await (await _requireSqlite()).writePlacement(key, config);
        _layoutWarnings[key] = _fallbackIssue(key);
      }
      return;
    }
    await _json.writePlacement(key, config);
    _layoutWarnings.remove(key);
  }

  Future<JsonLayoutBundle> _readBundle(String rawPath) async {
    final key = layoutDirectoryKey(rawPath);
    final preferred = await _preferredBackend();
    final jsonExists = await _json.exists(key);
    final sqliteHas = await _sqliteHas(key);

    if (preferred == MetadataBackend.sqlite) {
      if (!sqliteHas && jsonExists) {
        await _importJsonToSqlite(key);
        await _json.tryDelete(key);
      } else if (sqliteHas && jsonExists) {
        await _json.tryDelete(key);
      }
      final bundle = await (await _requireSqlite()).read(key);
      return JsonLayoutBundle(
        layout: bundle.layout,
        placement: bundle.placement,
        version: bundle.version,
      );
    }

    if (jsonExists) {
      try {
        final bundle = await _json.read(key);
        if (sqliteHas) {
          await _sqliteDeleteIfPresent(key);
        }
        return bundle;
      } catch (e) {
        if (sqliteHas) {
          _layoutWarnings[key] = _fallbackIssue(key);
          final bundle = await (await _requireSqlite()).read(key);
          return JsonLayoutBundle(
            layout: bundle.layout,
            placement: bundle.placement,
            version: bundle.version,
          );
        }
        rethrow;
      }
    }

    if (sqliteHas) {
      _layoutWarnings[key] = _fallbackIssue(key);
      final bundle = await (await _requireSqlite()).read(key);
      return JsonLayoutBundle(
        layout: bundle.layout,
        placement: bundle.placement,
        version: bundle.version,
      );
    }

    return JsonLayoutBundle(
      layout: {},
      placement: NewElementPlacementConfig.defaultConfig(),
      version: '1.0',
    );
  }

  Future<void> _mutate(
    String key, {
    required Future<void> Function() json,
    required Future<void> Function() sqlite,
  }) async {
    final preferred = await _preferredBackend();
    if (preferred == MetadataBackend.sqlite) {
      await sqlite();
      await _json.tryDelete(key);
      _layoutWarnings.remove(key);
      return;
    }
    if (await _json.exists(key)) {
      try {
        await json();
        await _sqliteDeleteIfPresent(key);
        _layoutWarnings.remove(key);
        return;
      } catch (e) {
        if (await _sqliteHas(key)) {
          await sqlite();
          _layoutWarnings[key] = _fallbackIssue(key);
          return;
        }
        rethrow;
      }
    }
    if (await _sqliteHas(key)) {
      await sqlite();
      _layoutWarnings[key] = _fallbackIssue(key);
      return;
    }
    await json();
    _layoutWarnings.remove(key);
  }

  Future<void> close() async {
    await _openedDb?.close();
    await _injectedDatabase?.close();
    _openedDb = null;
    _sqliteStore = null;
  }
}
