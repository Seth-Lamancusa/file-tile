import 'package:file_tile/src/models/edit_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the newest 50 edits and a new edit clears redo', () {
    final history = EditHistory();
    for (var i = 0; i < 60; i++) {
      history.push(MoveEdit(destDir: '$i', items: const []));
    }

    final undone = <String>[];
    while (history.canUndo) {
      final entry = history.takeUndo()! as MoveEdit;
      undone.add(entry.destDir);
      history.noteRedo(entry);
    }
    expect(undone, [for (var i = 59; i >= 10; i--) '$i']);
    expect(history.canRedo, isTrue);

    history.push(MoveEdit(destDir: 'fresh', items: const []));
    expect(history.canRedo, isFalse);
    expect((history.takeUndo()! as MoveEdit).destDir, 'fresh');
    expect(history.canUndo, isFalse);
  });
}
