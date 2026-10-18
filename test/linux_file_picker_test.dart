import 'dart:io';

import 'package:file_tile/src/utils/linux_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinuxFilePicker', () {
    test('pickFile asks zenity for a file and returns the chosen path',
        () async {
      late String executable;
      late List<String> arguments;
      final picker = LinuxFilePicker(run: (command, args) async {
        executable = command;
        arguments = args;
        return ProcessResult(0, 0, '/tmp/notes.txt\n', '');
      });

      final path = await picker.pickFile(initialDirectory: '/tmp/start');

      expect(executable, 'zenity');
      expect(arguments, [
        '--file-selection',
        '--title=Choose file',
        '--filename=/tmp/start/',
      ]);
      expect(path, '/tmp/notes.txt');
    });

    test('pickDirectory asks zenity for a folder', () async {
      late List<String> arguments;
      final picker = LinuxFilePicker(run: (_, args) async {
        arguments = args;
        return ProcessResult(0, 0, '/tmp/folder', '');
      });

      final path = await picker.pickDirectory(initialDirectory: '/tmp/folder');

      expect(arguments, contains('--directory'));
      expect(arguments, contains('--filename=/tmp/folder/'));
      expect(path, '/tmp/folder');
    });

    test('cancel returns null', () async {
      final picker = LinuxFilePicker(run: (_, __) async {
        return ProcessResult(0, 1, '', '');
      });

      expect(await picker.pickFile(initialDirectory: '/tmp'), isNull);
    });
  });
}
