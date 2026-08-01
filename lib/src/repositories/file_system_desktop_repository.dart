import 'dart:io';
import 'package:path/path.dart' as p;
import '../services/path_service.dart';
import '../utils/config_manager.dart';
import '../utils/metadata_helper.dart';
import 'desktop_repository.dart';

/// [DesktopRepository] implementation backed by the real filesystem.
///
/// Mostly wraps the existing `PathService`/`ConfigManager`/`MetadataManager`
/// logic that used to be called directly from `DesktopViewModel`.
class FileSystemDesktopRepository implements DesktopRepository {
  ConfigManager? _configManager;

  ConfigManager _getConfigManager() {
    return _configManager ??= ConfigManager(File(PathService.localConfigPath));
  }

  Future<void> _ensureConfigDirExists() async {
    final manager = _getConfigManager();
    if (!await manager.file.exists()) {
      await PathService.ensureDirsExist();
    }
  }

  @override
  String get initialDirectory => PathService.baseDir;

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<List<DesktopEntity>> listEntities(String path) async {
    final entities = await Directory(path).list().toList();
    return entities
        .map((e) => DesktopEntity(name: p.basename(e.path), isDirectory: e is Directory))
        .toList();
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
    if (await File(path).exists()) {
      await File(path).delete();
    } else if (await Directory(path).exists()) {
      await Directory(path).delete(recursive: true);
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
  Future<Map<String, dynamic>> readLayout(String path) async {
    final manager = MetadataManager(path);
    await manager.load();
    return Map<String, dynamic>.from(manager.layout);
  }

  @override
  Future<void> updateLayout(String path, Map<String, dynamic> layout) async {
    final manager = MetadataManager(path);
    await manager.load();
    await manager.updateLayout(layout);
  }
}
