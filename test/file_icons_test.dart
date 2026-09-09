import 'package:file_tile/src/utils/file_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('directories always use the folder icon', () {
    expect(iconForEntry('photos.png', isDirectory: true), Icons.folder);
  });

  test('maps common extensions', () {
    expect(iconForEntry('notes.md', isDirectory: false), Icons.article);
    expect(iconForEntry('app.dart', isDirectory: false), Icons.code);
    expect(iconForEntry('shot.PNG', isDirectory: false), Icons.image);
    expect(iconForEntry('archive.zip', isDirectory: false), Icons.folder_zip);
    expect(iconForEntry('unknown', isDirectory: false), Icons.description);
  });

  test('raster image detection is extension-based', () {
    expect(isRasterImageFile('a.jpg'), isTrue);
    expect(isRasterImageFile('a.SVG'), isFalse);
    expect(isRasterImageFile('a.pdf'), isFalse);
  });
}
