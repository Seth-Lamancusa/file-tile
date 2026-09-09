import 'dart:convert';
import 'dart:io';

import 'package:file_tile/src/models/metadata_backend.dart';
import 'package:file_tile/src/models/new_element_placement_config.dart';
import 'package:file_tile/src/repositories/file_system_desktop_repository.dart';
import 'package:file_tile/src/services/path_service.dart';
import 'package:file_tile/src/storage/layout_database.dart';
import 'package:file_tile/src/utils/metadata_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late LayoutDatabase db;
  late FileSystemDesktopRepository repo;
  late String folderPath;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('file_tile_sqlite_layout');
    await PathService.init(tempDir.path);
    folderPath = p.join(tempDir.path, 'proj');
    Directory(folderPath).createSync();
    db = LayoutDatabase.memory();
    repo = FileSystemDesktopRepository(layoutDatabase: db);
  });

  tearDown(() async {
    await repo.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Map<String, dynamic> layoutJson(Map<String, dynamic> layout) => {
        'layout': layout,
        'version': '1.0',
        'newElementPlacementConfig':
            NewElementPlacementConfig.defaultConfig().toJson(),
      };

  File jsonFile() => File(p.join(folderPath, MetadataManager.fileName));

  test('sqlite round-trip layout and rename', () async {
    await repo.setMetadataBackend(MetadataBackend.sqlite);
    await repo.updateLayout(folderPath, {
      'a.txt': {'x': 80.0, 'y': 0.0},
    });
    await repo.renameInLayout(folderPath, 'a.txt', 'b.txt');
    final layout = await repo.readLayout(folderPath);
    expect(layout['b.txt']['x'], 80.0);
    expect(layout.containsKey('a.txt'), isFalse);
    expect(jsonFile().existsSync(), isFalse);
  });

  test('switch to sqlite imports known json then deletes it', () async {
    await jsonFile().writeAsString(json.encode(layoutJson({
      'photo.jpg': {'x': 160.0, 'y': 80.0},
    })));
    await repo.updateConfig((c) {
      c['last_visited_directory'] = folderPath;
      return c;
    });

    await repo.setMetadataBackend(MetadataBackend.sqlite);

    expect(jsonFile().existsSync(), isFalse);
    final layout = await repo.readLayout(folderPath);
    expect(layout['photo.jpg']['y'], 80.0);
  });

  test('does not overwrite sqlite when the path is already in the db',
      () async {
    await repo.setMetadataBackend(MetadataBackend.sqlite);
    await repo.updateLayout(folderPath, {
      'kept.txt': {'x': 1.0, 'y': 2.0},
    });
    await jsonFile().writeAsString(json.encode(layoutJson({
      'other.txt': {'x': 9.0, 'y': 9.0},
    })));
    await repo.updateConfig((c) {
      c['last_visited_directory'] = folderPath;
      return c;
    });

    await repo.setMetadataBackend(MetadataBackend.sqlite);
    final layout = await repo.readLayout(folderPath);
    expect(layout['kept.txt']['x'], 1.0);
    expect(layout.containsKey('other.txt'), isFalse);
  });

  test('failed json import leaves json in place and does not insert defaults',
      () async {
    await jsonFile().writeAsString('not-json');
    await repo.updateConfig((c) {
      c['last_visited_directory'] = folderPath;
      return c;
    });

    await repo.setMetadataBackend(MetadataBackend.sqlite);

    expect(jsonFile().existsSync(), isTrue);
    expect(
      () => repo.readLayout(folderPath),
      throwsA(isA<FormatException>()),
    );
  });

  test('json leftover is used when export cannot write the folder', () async {
    await repo.setMetadataBackend(MetadataBackend.sqlite);
    await repo.updateLayout(folderPath, {
      'saved.txt': {'x': 40.0, 'y': 0.0},
    });

    // Remove write permission so exporting JSON fails, then switch back.
    await Process.run('chmod', ['a-w', folderPath]);
    addTearDown(() => Process.run('chmod', ['u+w', folderPath]));

    await repo.setMetadataBackend(MetadataBackend.json);

    final layout = await repo.readLayout(folderPath);
    expect(layout['saved.txt']['x'], 40.0);
    expect(repo.takeLayoutWarning(folderPath), isNotNull);
  }, skip: !Platform.isLinux ? 'chmod leftover test is Linux-only' : false);
}
