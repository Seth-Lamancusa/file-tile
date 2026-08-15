import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/services/linux_url_handler_registrar.dart';

void main() {
  group('buildDesktopEntryContent', () {
    test('includes the mime type, name, and quoted exec path', () {
      final content = buildDesktopEntryContent('/home/user/File Tile.AppImage');

      expect(content, contains('Name=File Tile'));
      expect(content, contains('MimeType=x-scheme-handler/filetile;'));
      expect(content, contains('Exec="/home/user/File Tile.AppImage" %u'));
      expect(content, contains('Type=Application'));
      expect(content, contains('NoDisplay=true'));
    });
  });

  group('needsUpdate', () {
    test('is true when no file exists yet', () {
      expect(needsUpdate(null, 'desired'), isTrue);
    });

    test('is false when content already matches', () {
      expect(needsUpdate('same', 'same'), isFalse);
    });

    test('is true when content differs, e.g. the exec path changed', () {
      expect(needsUpdate('old content', 'new content'), isTrue);
    });
  });
}
