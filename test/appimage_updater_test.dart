import 'dart:io';

import 'package:file_tile/src/services/appimage_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('statusFromCheckExitCode', () {
    test('0 means the AppImage is already current', () {
      expect(statusFromCheckExitCode(0), AppImageUpdateStatus.upToDate);
    });

    test('1 means an update is available', () {
      expect(
        statusFromCheckExitCode(1),
        AppImageUpdateStatus.updateAvailable,
      );
    });

    test('any other code means the check could not be completed', () {
      expect(statusFromCheckExitCode(2), AppImageUpdateStatus.unavailable);
      expect(statusFromCheckExitCode(-1), AppImageUpdateStatus.unavailable);
    });
  });

  group('bundledUpdaterPath', () {
    test('points at usr/bin inside APPDIR when the file exists', () {
      expect(
        bundledUpdaterPath(
          environment: {'APPDIR': '/tmp/.mount_filetile'},
          exists: (path) =>
              path == '/tmp/.mount_filetile/usr/bin/appimageupdatetool',
        ),
        '/tmp/.mount_filetile/usr/bin/appimageupdatetool',
      );
    });

    test('is null when the bundle does not contain the tool', () {
      expect(
        bundledUpdaterPath(
          environment: {'APPDIR': '/tmp/.mount_filetile'},
          exists: (_) => false,
        ),
        isNull,
      );
    });

    test('is null outside an AppImage', () {
      expect(
        bundledUpdaterPath(environment: const {}, exists: (_) => true),
        isNull,
      );
    });
  });

  group('environmentForRelaunch', () {
    test('drops the running AppImage mount variables', () {
      final env = environmentForRelaunch({
        'HOME': '/home/seth',
        'PATH': '/usr/bin',
        'APPIMAGE': '/home/seth/FileTile.AppImage',
        'APPDIR': '/tmp/.mount_x',
        'LD_LIBRARY_PATH': '/tmp/.mount_x/usr/lib',
        'ARGV0': 'FileTile.AppImage',
        'OWD': '/home/seth',
      });

      expect(env['HOME'], '/home/seth');
      expect(env['PATH'], '/usr/bin');
      expect(env.containsKey('APPIMAGE'), isFalse);
      expect(env.containsKey('APPDIR'), isFalse);
      expect(env.containsKey('LD_LIBRARY_PATH'), isFalse);
      expect(env.containsKey('ARGV0'), isFalse);
      expect(env.containsKey('OWD'), isFalse);
    });
  });

  group('summarizeToolError', () {
    test('uses the exit code when the tool wrote nothing', () {
      expect(summarizeToolError('  ', 3), 'The updater exited with code 3.');
    });

    test('keeps the last few lines of stderr', () {
      expect(
        summarizeToolError('one\ntwo\nthree\nfour\nfive\n', 1),
        'two\nthree\nfour\nfive',
      );
    });
  });

  group('AppImageUpdater', () {
    test('stays quiet when APPIMAGE is unset', () async {
      final updater = AppImageUpdater(
        environment: const {},
        fileExists: (_) => true,
        run: (_, __, ___) async => fail('should not run'),
      );

      expect(await updater.checkForUpdate(), AppImageUpdateStatus.unavailable);
    });

    test('reports an available update from exit code 1', () async {
      late List<String> args;
      final updater = AppImageUpdater(
        environment: const {
          'APPIMAGE': '/home/seth/FileTile.AppImage',
          'APPDIR': '/tmp/.mount_filetile',
        },
        fileExists: (_) => true,
        run: (executable, arguments, environment) async {
          expect(executable, '/tmp/.mount_filetile/usr/bin/appimageupdatetool');
          expect(environment['APPIMAGE_EXTRACT_AND_RUN'], '1');
          expect(environment['LD_LIBRARY_PATH'], '');
          args = arguments;
          return ProcessResult(1, 1, '', '');
        },
      );

      expect(
        await updater.checkForUpdate(),
        AppImageUpdateStatus.updateAvailable,
      );
      expect(args, ['--check-for-update', '/home/seth/FileTile.AppImage']);
    });

    test('treats a failed check as unavailable', () async {
      final updater = AppImageUpdater(
        environment: const {
          'APPIMAGE': '/home/seth/FileTile.AppImage',
          'APPDIR': '/tmp/.mount_filetile',
        },
        fileExists: (_) => true,
        run: (_, __, ___) async =>
            ProcessResult(1, 7, '', 'no update information'),
      );

      expect(await updater.checkForUpdate(), AppImageUpdateStatus.unavailable);
    });

    test('installs by overwriting the running AppImage', () async {
      late List<String> args;
      final updater = AppImageUpdater(
        environment: const {
          'APPIMAGE': '/home/seth/FileTile.AppImage',
          'APPDIR': '/tmp/.mount_filetile',
        },
        fileExists: (_) => true,
        run: (_, arguments, __) async {
          args = arguments;
          return ProcessResult(1, 0, '', '');
        },
      );

      final result = await updater.installUpdate();
      expect(result.installed, isTrue);
      expect(args, ['--overwrite', '/home/seth/FileTile.AppImage']);
    });

    test('returns the tool error when overwrite fails', () async {
      final updater = AppImageUpdater(
        environment: const {
          'APPIMAGE': '/home/seth/FileTile.AppImage',
          'APPDIR': '/tmp/.mount_filetile',
        },
        fileExists: (_) => true,
        run: (_, __, ___) async =>
            ProcessResult(1, 2, '', 'signature mismatch'),
      );

      final result = await updater.installUpdate();
      expect(result.installed, isFalse);
      expect(result.message, 'signature mismatch');
    });

    test('relaunch starts the AppImage and exits', () async {
      String? started;
      Map<String, String>? startedEnv;
      int? exited;
      final updater = AppImageUpdater(
        environment: const {
          'APPIMAGE': '/home/seth/FileTile.AppImage',
          'HOME': '/home/seth',
          'LD_LIBRARY_PATH': '/tmp/.mount_x/usr/lib',
        },
        startDetached: (executable, environment) async {
          started = executable;
          startedEnv = environment;
        },
        exitProcess: (code) => exited = code,
      );

      await updater.relaunch();
      expect(started, '/home/seth/FileTile.AppImage');
      expect(startedEnv!['HOME'], '/home/seth');
      expect(startedEnv!.containsKey('LD_LIBRARY_PATH'), isFalse);
      expect(exited, 0);
    });
  });
}
