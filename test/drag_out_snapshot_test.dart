import 'dart:io';

import 'package:file_tile/src/utils/drag_out_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('file-tile-drag-snapshot');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  String scratch(String _) => p.join(root.path, 'stash');

  test('a deleted file can be put back from the snapshot', () async {
    final docs = Directory(p.join(root.path, 'docs'));
    await docs.create();
    final file = File(p.join(docs.path, 'notes.txt'));
    await file.writeAsString('hello');
    final snapshot = await DragOutSnapshot.capture(
      [file.path],
      scratchDirectoryFor: scratch,
    );

    await file.delete();
    expect(await snapshot.putBack(file.path), isTrue);
    expect(await File(file.path).readAsString(), 'hello');
    await snapshot.discard();
  });

  test('a deleted folder comes back with its contents', () async {
    final docs = Directory(p.join(root.path, 'docs'));
    final folder = Directory(p.join(docs.path, 'photos'));
    await folder.create(recursive: true);
    await File(p.join(folder.path, 'a.txt')).writeAsString('nested');
    final snapshot = await DragOutSnapshot.capture(
      [folder.path],
      scratchDirectoryFor: scratch,
    );

    await folder.delete(recursive: true);
    expect(await snapshot.putBack(folder.path), isTrue);
    expect(await File(p.join(folder.path, 'a.txt')).readAsString(), 'nested');
    await snapshot.discard();
  });

  test('a symlink is restored as a symlink', () async {
    final docs = Directory(p.join(root.path, 'docs'));
    await docs.create();
    final link = Link(p.join(docs.path, 'shortcut'));
    await link.create('target.txt');
    final snapshot = await DragOutSnapshot.capture(
      [link.path],
      scratchDirectoryFor: scratch,
    );

    await link.delete();
    expect(await snapshot.putBack(link.path), isTrue);
    expect(await Link(link.path).target(), 'target.txt');
    await snapshot.discard();
  });

  test('discard removes the snapshot and leaves the original', () async {
    final docs = Directory(p.join(root.path, 'docs'));
    await docs.create();
    final file = File(p.join(docs.path, 'notes.txt'));
    await file.writeAsString('hello');
    final snapshot = await DragOutSnapshot.capture(
      [file.path],
      scratchDirectoryFor: scratch,
    );

    await snapshot.discard();
    expect(await file.readAsString(), 'hello');
    expect(await snapshot.putBack(file.path), isFalse);
    final leftover = Directory(scratch(''));
    if (await leftover.exists()) {
      expect(await leftover.list().length, 0);
    }
  });

  test('putBack refuses to replace a file that is still there', () async {
    final docs = Directory(p.join(root.path, 'docs'));
    await docs.create();
    final file = File(p.join(docs.path, 'notes.txt'));
    await file.writeAsString('hello');
    final snapshot = await DragOutSnapshot.capture(
      [file.path],
      scratchDirectoryFor: scratch,
    );

    expect(await snapshot.putBack(file.path), isFalse);
    expect(await file.readAsString(), 'hello');
    await snapshot.discard();
  });
}
