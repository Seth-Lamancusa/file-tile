import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/repositories/file_system_desktop_repository.dart';
import 'package:file_tile/src/utils/metadata_helper.dart';

void main() {
  test('metadata file is created on readLayout+updateLayout against real filesystem', () async {
    final testDir = '/tmp/file-tile-test-folder';
    final metadataFile = File('$testDir/file-tile.json');
    if (await metadataFile.exists()) await metadataFile.delete();

    expect(await metadataFile.exists(), false, reason: 'should not exist before test');

    final repo = FileSystemDesktopRepository();
    final layout = await repo.readLayout(testDir);
    await repo.updateLayout(testDir, layout);

    expect(await metadataFile.exists(), true, reason: 'metadata file should be created');
    print('Contents: ${await metadataFile.readAsString()}');
  });

  test('a pre-existing legacy stitch-grid.json is renamed to file-tile.json in place', () async {
    final testDir = Directory.systemTemp.createTempSync('file_tile_metadata_migration_test');
    addTearDown(() => testDir.deleteSync(recursive: true));

    final legacyFile = File('${testDir.path}/${MetadataManager.legacyFileName}');
    final newFile = File('${testDir.path}/${MetadataManager.fileName}');
    await legacyFile.writeAsString(json.encode({
      'layout': {'foo.txt': 1},
      'version': '1.0',
    }));

    final repo = FileSystemDesktopRepository();
    final layout = await repo.readLayout(testDir.path);

    expect(await legacyFile.exists(), false, reason: 'legacy metadata file should be renamed away');
    expect(await newFile.exists(), true);
    expect(layout['foo.txt'], 1, reason: 'existing layout positions must be preserved');
  });
}
