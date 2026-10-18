import 'dart:io';

import 'package:file_tile/src/utils/trash_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('percent-encoding keeps slashes and escapes spaces', () {
    expect(
      percentEncodeTrashPath('/tmp/my notes.txt'),
      '/tmp/my%20notes.txt',
    );
    expect(
      percentDecodeTrashPath('/tmp/my%20notes.txt'),
      '/tmp/my notes.txt',
    );
  });

  test('trash and restore round-trip, including a name collision', () async {
    final root = await Directory.systemTemp.createTemp('file-tile-trash');
    addTearDown(() => root.delete(recursive: true));
    final trash = Directory(p.join(root.path, 'Trash'));
    final origin = Directory(p.join(root.path, 'docs'));
    await origin.create();
    final first = File(p.join(origin.path, 'notes.txt'));
    await first.writeAsString('one');
    final token = await moveToTrashDirectory(first.path, trashDirectory: trash.path);
    expect(await first.exists(), isFalse);
    expect(await File(token.trashedPath).readAsString(), 'one');
    expect(await File(token.infoPath).readAsString(), contains('Path='));

    final second = File(p.join(origin.path, 'notes.txt'));
    await second.writeAsString('two');
    final again =
        await moveToTrashDirectory(second.path, trashDirectory: trash.path);
    expect(p.basename(again.trashedPath), isNot(p.basename(token.trashedPath)));

    await restoreFromTrash(token);
    expect(await File(first.path).readAsString(), 'one');
    expect(await File(token.infoPath).exists(), isFalse);

    await second.create();
    await expectLater(
      restoreFromTrash(again),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(again.trashedPath).exists(), isTrue);
  });
}
