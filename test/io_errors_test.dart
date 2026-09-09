import 'dart:io';

import 'package:file_tile/src/models/directory_layout_issue.dart';
import 'package:file_tile/src/utils/io_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyLayoutIoError', () {
    test('maps EACCES to permissionDenied', () {
      final error = FileSystemException(
        'Failed',
        '/tmp/file-tile.json',
        const OSError('Permission denied', 13),
      );
      expect(classifyLayoutIoError(error),
          DirectoryLayoutIssueKind.permissionDenied);
      expect(isPermissionDenied(error), isTrue);
    });

    test('maps FormatException to corrupt', () {
      expect(
        classifyLayoutIoError(const FormatException('bad json')),
        DirectoryLayoutIssueKind.corrupt,
      );
    });

    test('maps other IO errors to unreadable', () {
      final error = FileSystemException(
        'Failed',
        '/tmp/file-tile.json',
        const OSError('I/O error', 16),
      );
      expect(classifyLayoutIoError(error), DirectoryLayoutIssueKind.unreadable);
    });
  });
}
