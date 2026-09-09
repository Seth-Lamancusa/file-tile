import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/utils/copy_names.dart';

void main() {
  test('leaves a free name unchanged', () {
    expect(uniqueCopyName('a.txt', {'b.txt'}), 'a.txt');
  });

  test('appends (copy) and then a number', () {
    expect(uniqueCopyName('a.txt', {'a.txt'}), 'a (copy).txt');
    expect(
        uniqueCopyName('a.txt', {'a.txt', 'a (copy).txt'}), 'a (copy 2).txt');
  });
}
