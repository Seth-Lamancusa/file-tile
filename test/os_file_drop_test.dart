import 'package:flutter_test/flutter_test.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:file_tile/src/utils/os_file_drop.dart';

void main() {
  group('preferredOsDropOperation', () {
    test('defaults to move when the source allows it', () {
      expect(
        preferredOsDropOperation(
          controlPressed: false,
          allowed: {DropOperation.move, DropOperation.copy},
        ),
        DropOperation.move,
      );
    });

    test('Ctrl selects copy when allowed', () {
      expect(
        preferredOsDropOperation(
          controlPressed: true,
          allowed: {DropOperation.move, DropOperation.copy},
        ),
        DropOperation.copy,
      );
    });

    test('falls back to copy when move is not allowed', () {
      expect(
        preferredOsDropOperation(
          controlPressed: false,
          allowed: {DropOperation.copy},
        ),
        DropOperation.copy,
      );
    });
  });

  group('osFileDragOutOperations', () {
    test('offers move and copy so browsers can accept the drop', () {
      expect(
        osFileDragOutOperations(controlPressed: false),
        [DropOperation.move, DropOperation.copy],
      );
    });

    test('Ctrl is copy-only', () {
      expect(
        osFileDragOutOperations(controlPressed: true),
        [DropOperation.copy],
      );
    });
  });

  test('isFileTileLocalData recognizes outbound sessions', () {
    expect(isFileTileLocalData({fileTileDragLocalKey: true}), isTrue);
    expect(isFileTileLocalData({'other': true}), isFalse);
    expect(isFileTileLocalData(null), isFalse);
  });

  group('isDropIntoSelf', () {
    test('rejects dropping a folder onto itself', () {
      expect(isDropIntoSelf('/root/foo', ['/root/foo']), isTrue);
    });

    test('rejects dropping into a nested path of the source folder', () {
      expect(isDropIntoSelf('/root/foo/bar', ['/root/foo']), isTrue);
    });

    test('allows dropping onto a sibling', () {
      expect(isDropIntoSelf('/root/bar', ['/root/foo']), isFalse);
    });
  });
}
