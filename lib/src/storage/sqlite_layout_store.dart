import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/new_element_placement_config.dart';
import 'layout_database.dart';

class SqliteLayoutBundle {
  final Map<String, dynamic> layout;
  final NewElementPlacementConfig placement;
  final String version;

  const SqliteLayoutBundle({
    required this.layout,
    required this.placement,
    required this.version,
  });
}

class SqliteLayoutStore {
  SqliteLayoutStore(this.db);

  final LayoutDatabase db;

  Future<bool> hasDirectory(String path) async {
    final row = await (db.select(db.directoryMetas)
          ..where((t) => t.path.equals(path)))
        .getSingleOrNull();
    return row != null;
  }

  Future<List<String>> directoryPaths() async {
    final rows = await db.select(db.directoryMetas).get();
    return [for (final row in rows) row.path];
  }

  Future<SqliteLayoutBundle> read(String path) async {
    final meta = await (db.select(db.directoryMetas)
          ..where((t) => t.path.equals(path)))
        .getSingleOrNull();
    if (meta == null) {
      return SqliteLayoutBundle(
        layout: {},
        placement: NewElementPlacementConfig.defaultConfig(),
        version: '1.0',
      );
    }
    final nodes = await (db.select(db.layoutNodes)
          ..where((t) => t.path.equals(path)))
        .get();
    final layout = <String, dynamic>{};
    for (final node in nodes) {
      layout[node.name] = json.decode(node.payload);
    }
    final placementMap =
        (json.decode(meta.placementJson) as Map).cast<String, dynamic>();
    return SqliteLayoutBundle(
      layout: layout,
      placement: NewElementPlacementConfig.fromJson(placementMap),
      version: meta.version,
    );
  }

  Future<void> writeLayout(String path, Map<String, dynamic> layout) async {
    await db.transaction(() async {
      await _ensureMeta(path);
      await (db.delete(db.layoutNodes)..where((t) => t.path.equals(path)))
          .go();
      await _insertNodes(path, layout);
    });
  }

  Future<void> writePlacement(
      String path, NewElementPlacementConfig config) async {
    await db.transaction(() async {
      final existing = await _meta(path);
      await db.into(db.directoryMetas).insertOnConflictUpdate(
            DirectoryMetasCompanion(
              path: Value(path),
              placementJson: Value(json.encode(config.toJson())),
              version: Value(existing?.version ?? '1.0'),
            ),
          );
    });
  }

  Future<void> writeAll(String path, SqliteLayoutBundle bundle) async {
    await db.transaction(() async {
      await db.into(db.directoryMetas).insertOnConflictUpdate(
            DirectoryMetasCompanion(
              path: Value(path),
              placementJson: Value(json.encode(bundle.placement.toJson())),
              version: Value(bundle.version),
            ),
          );
      await (db.delete(db.layoutNodes)..where((t) => t.path.equals(path)))
          .go();
      await _insertNodes(path, bundle.layout);
    });
  }

  Future<void> removeNode(String path, String name) async {
    await db.transaction(() async {
      await _ensureMeta(path);
      await (db.delete(db.layoutNodes)
            ..where((t) => t.path.equals(path) & t.name.equals(name)))
          .go();
    });
  }

  Future<void> renameNode(String path, String oldName, String newName) async {
    await db.transaction(() async {
      final row = await (db.select(db.layoutNodes)
            ..where((t) => t.path.equals(path) & t.name.equals(oldName)))
          .getSingleOrNull();
      if (row == null) return;
      await (db.delete(db.layoutNodes)
            ..where((t) => t.path.equals(path) & t.name.equals(oldName)))
          .go();
      await db.into(db.layoutNodes).insert(
            LayoutNodesCompanion(
              path: Value(path),
              name: Value(newName),
              payload: Value(row.payload),
            ),
          );
    });
  }

  Future<void> deleteDirectory(String path) async {
    await db.transaction(() async {
      await (db.delete(db.layoutNodes)..where((t) => t.path.equals(path)))
          .go();
      await (db.delete(db.directoryMetas)..where((t) => t.path.equals(path)))
          .go();
    });
  }

  Future<DirectoryMeta?> _meta(String path) {
    return (db.select(db.directoryMetas)..where((t) => t.path.equals(path)))
        .getSingleOrNull();
  }

  Future<void> _ensureMeta(String path) async {
    final existing = await _meta(path);
    if (existing != null) return;
    await db.into(db.directoryMetas).insert(
          DirectoryMetasCompanion(
            path: Value(path),
            placementJson: Value(
                json.encode(NewElementPlacementConfig.defaultConfig().toJson())),
            version: Value('1.0'),
          ),
        );
  }

  Future<void> _insertNodes(String path, Map<String, dynamic> layout) async {
    for (final entry in layout.entries) {
      await db.into(db.layoutNodes).insert(
            LayoutNodesCompanion(
              path: Value(path),
              name: Value(entry.key),
              payload: Value(json.encode(entry.value)),
            ),
          );
    }
  }
}
