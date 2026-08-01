import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitch_desktop_grid/src/repositories/file_system_desktop_repository.dart';

void main() {
  test('metadata file is created on readLayout+updateLayout against real filesystem', () async {
    final testDir = '/tmp/stitch-test-folder';
    final metadataFile = File('$testDir/stitch-grid.json');
    if (await metadataFile.exists()) await metadataFile.delete();

    expect(await metadataFile.exists(), false, reason: 'should not exist before test');

    final repo = FileSystemDesktopRepository();
    final layout = await repo.readLayout(testDir);
    await repo.updateLayout(testDir, layout);

    expect(await metadataFile.exists(), true, reason: 'metadata file should be created');
    print('Contents: ${await metadataFile.readAsString()}');
  });
}
