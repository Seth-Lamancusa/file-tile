import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final wrapper = '$root/linux/packaging/appimage/bin/appimagetool';
  final bundleScript = '$root/linux/packaging/appimage/bundle_updater.sh';

  test('wrapper inserts update information ahead of appimagetool args',
      () async {
    final temp = await Directory.systemTemp.createTemp('file-tile-appimage');
    addTearDown(() => temp.delete(recursive: true));
    final out = File('${temp.path}/args');
    final fakeBin = Directory('${temp.path}/bin')..createSync();
    final fake = File('${fakeBin.path}/appimagetool');
    await fake.writeAsString('''#!/bin/sh
printf '%s\\n' "\$@" > "${out.path}"
''');
    await Process.run('chmod', ['+x', fake.path, wrapper]);

    final result = await Process.run(
      wrapper,
      ['--no-appstream', 'AppDir', 'out.AppImage'],
      environment: {
        'PATH': '${fakeBin.path}:/usr/bin:/bin',
        'FILE_TILE_UPDATE_INFORMATION':
            'zsync|https://updates.example.com/file_tile-latest-linux.AppImage.zsync',
      },
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      await out.readAsLines(),
      [
        '--updateinformation',
        'zsync|https://updates.example.com/file_tile-latest-linux.AppImage.zsync',
        '--no-appstream',
        'AppDir',
        'out.AppImage',
      ],
    );
  });

  test('wrapper leaves appimagetool alone while the host line is commented',
      () async {
    final temp = await Directory.systemTemp.createTemp('file-tile-appimage');
    addTearDown(() => temp.delete(recursive: true));
    final out = File('${temp.path}/args');
    final fakeBin = Directory('${temp.path}/bin')..createSync();
    final fake = File('${fakeBin.path}/appimagetool');
    await fake.writeAsString('''#!/bin/sh
printf '%s\\n' "\$@" > "${out.path}"
''');
    final commented = File('${temp.path}/update_information')
      ..writeAsStringSync('# gh-releases-zsync|owner|repo|latest|*.zsync\n');
    await Process.run('chmod', ['+x', fake.path, wrapper]);

    final result = await Process.run(
      wrapper,
      ['--no-appstream', 'AppDir', 'out.AppImage'],
      environment: {
        'PATH': '${fakeBin.path}:/usr/bin:/bin',
        'FILE_TILE_UPDATE_INFORMATION': '',
        'FILE_TILE_UPDATE_INFORMATION_FILE': commented.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      await out.readAsLines(),
      ['--no-appstream', 'AppDir', 'out.AppImage'],
    );
  });

  test('update information targets GitHub releases for this repo', () {
    final lines = File('$root/linux/packaging/appimage/update_information')
        .readAsLinesSync()
        .map((line) => line.replaceFirst(RegExp(r'\s*#.*'), '').trim())
        .where((line) => line.isNotEmpty);

    expect(lines, [
      'gh-releases-zsync|Seth-Lamancusa|file-tile|latest|file_tile-*linux.AppImage.zsync',
    ]);
  });

  test('bundle hook copies the updater into the Flutter bundle', () async {
    final temp = await Directory.systemTemp.createTemp('file-tile-bundle');
    addTearDown(() => temp.delete(recursive: true));
    final tool = File('${temp.path}/appimageupdatetool-src');
    await tool.writeAsString('#!/bin/sh\necho updater\n');
    final bundle = Directory('${temp.path}/bundle')..createSync();
    await Process.run('chmod', ['+x', tool.path, bundleScript]);

    final result = await Process.run(
      bundleScript,
      const [],
      environment: {
        'PATH': '/usr/bin:/bin',
        'FILE_TILE_UPDATER_BIN': tool.path,
        'BUILD_OUTPUT_DIRECTORY': bundle.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final copied = File('${bundle.path}/usr/bin/appimageupdatetool');
    expect(await copied.readAsString(), await tool.readAsString());
    expect(await copied.stat().then((s) => s.mode & 0x49), isNonZero);
  });
}
