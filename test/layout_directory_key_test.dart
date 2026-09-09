import 'package:file_tile/src/utils/layout_directory_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('strips a trailing separator except for root', () {
    expect(layoutDirectoryKey('/tmp/proj/'), '/tmp/proj');
    expect(layoutDirectoryKey('/'), '/');
  });

  test('normalizes relative segments', () {
    expect(layoutDirectoryKey('/tmp/proj/./nested/..'), '/tmp/proj');
  });

  test('makes relative paths absolute', () {
    final key = layoutDirectoryKey('rel-dir');
    expect(p.isAbsolute(key), isTrue);
    expect(key.endsWith('rel-dir'), isTrue);
  });
}
