import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/new_element_placement_config.dart';
import '../utils/metadata_helper.dart';

class JsonLayoutBundle {
  final Map<String, dynamic> layout;
  final NewElementPlacementConfig placement;
  final String version;

  const JsonLayoutBundle({
    required this.layout,
    required this.placement,
    required this.version,
  });
}

class JsonLayoutStore {
  File _file(String directoryPath, String name) =>
      File(p.join(directoryPath, name));

  Future<bool> exists(String directoryPath) async {
    return await _file(directoryPath, MetadataManager.fileName).exists() ||
        await _file(directoryPath, MetadataManager.legacyFileName).exists();
  }

  Future<void> ensureExists(String directoryPath) async {
    await MetadataManager(directoryPath).ensureExists();
  }

  Future<JsonLayoutBundle> read(String directoryPath) async {
    final manager = MetadataManager(directoryPath);
    await manager.load();
    return JsonLayoutBundle(
      layout: Map<String, dynamic>.from(manager.layout),
      placement: manager.newElementPlacementConfig,
      version: manager.version,
    );
  }

  Future<void> writeLayout(
      String directoryPath, Map<String, dynamic> layout) async {
    final manager = MetadataManager(directoryPath);
    await manager.load();
    await manager.updateLayout(layout);
  }

  Future<void> writePlacement(
      String directoryPath, NewElementPlacementConfig config) async {
    final manager = MetadataManager(directoryPath);
    await manager.load();
    await manager.updateNewElementPlacementConfig(config);
  }

  Future<void> writeAll(String directoryPath, JsonLayoutBundle bundle) async {
    final manager = MetadataManager(directoryPath);
    await manager.ensureExists();
    await manager.load();
    await manager.updateLayout(bundle.layout);
    await manager.updateNewElementPlacementConfig(bundle.placement);
  }

  Future<void> removeNode(String directoryPath, String name) async {
    await MetadataManager(directoryPath).removeNode(name);
  }

  Future<void> renameNode(
      String directoryPath, String oldName, String newName) async {
    await MetadataManager(directoryPath).renameNode(oldName, newName);
  }

  /// Best-effort delete. Returns false if a file existed but could not be removed.
  Future<bool> tryDelete(String directoryPath) async {
    var failed = false;
    for (final name in [
      MetadataManager.fileName,
      MetadataManager.legacyFileName,
    ]) {
      final file = _file(directoryPath, name);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        failed = true;
      }
    }
    return !failed;
  }
}
