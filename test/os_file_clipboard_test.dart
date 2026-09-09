import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/utils/os_file_clipboard.dart';

void main() {
  group('parseGnomeCopiedFiles', () {
    test('reads copy payloads into file paths', () {
      final parsed = parseGnomeCopiedFiles(
        'copy\nfile:///home/seth/code/a.txt\nfile:///home/seth/code/b.txt\n',
      );
      expect(parsed, isNotNull);
      expect(parsed!.isCut, isFalse);
      expect(parsed.paths, [
        '/home/seth/code/a.txt',
        '/home/seth/code/b.txt',
      ]);
    });

    test('reads cut payloads', () {
      final parsed = parseGnomeCopiedFiles('cut\nfile:///tmp/x');
      expect(parsed!.isCut, isTrue);
      expect(parsed.paths, ['/tmp/x']);
    });
  });

  test('encodeGnomeCopiedFiles round-trips through the parser', () {
    final encoded = encodeGnomeCopiedFiles(
      const ['/tmp/one space.txt'],
      isCut: true,
    );
    final parsed = parseGnomeCopiedFiles(encoded);
    expect(parsed!.isCut, isTrue);
    expect(parsed.paths, ['/tmp/one space.txt']);
  });

  test('parseFileUriList reads every file URI and skips comments', () {
    expect(
      parseFileUriList(
        '# comment\r\nfile:///tmp/a.txt\r\nfile:///tmp/b.txt\r\n',
      ),
      ['/tmp/a.txt', '/tmp/b.txt'],
    );
  });
}
