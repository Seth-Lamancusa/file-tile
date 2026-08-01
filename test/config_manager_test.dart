import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stitch_desktop_grid/src/utils/config_manager.dart';

void main() {
  group('ConfigManager concurrent updates', () {
    late Directory tempDir;
    late File configFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('config_manager_test');
      configFile = File('${tempDir.path}/config.json');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('overlapping update() calls do not clobber each other\'s keys', () async {
      final manager = ConfigManager(configFile);
      await manager.load();

      // Fire many concurrent read-modify-write updates without awaiting
      // each one individually, mirroring rapid setting toggles / scroll
      // events firing updateConfig back-to-back in the real app.
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(manager.update((config) {
          config['key_$i'] = i;
          return config;
        }));
      }
      await Future.wait(futures);

      final onDisk = json.decode(await configFile.readAsString()) as Map<String, dynamic>;
      for (var i = 0; i < 20; i++) {
        expect(onDisk['key_$i'], i, reason: 'update for key_$i was lost to a race');
      }
    });

    test('a stale full-snapshot write (old loadDirectory pattern) would lose a concurrent update -- demonstrates why it must use update() instead', () async {
      final manager = ConfigManager(configFile);
      await manager.load();
      await manager.update((c) {
        c['invert_vertical_scroll'] = false;
        return c;
      });

      // Old buggy loadDirectory shape: read a full snapshot, do other async
      // disk work (listEntities/readLayout), then write the stale snapshot
      // back wholesale via save() -- exactly what writeConfig() used to do.
      final staleSnapshotWrite = () async {
        final snapshot = await manager.loadData();
        await Future.delayed(const Duration(milliseconds: 20));
        snapshot['last_visited_directory'] = '/some/dir';
        await manager.save(snapshot);
      }();

      // Concurrently, the user flips the scroll setting via the real,
      // fixed update() path.
      final settingToggle = Future.delayed(const Duration(milliseconds: 5), () {
        return manager.update((c) {
          c['invert_vertical_scroll'] = true;
          return c;
        });
      });

      await Future.wait([staleSnapshotWrite, settingToggle]);

      final onDisk = json.decode(await configFile.readAsString()) as Map<String, dynamic>;
      expect(onDisk['last_visited_directory'], '/some/dir');
      // Demonstrates the bug: the stale snapshot (taken before the toggle)
      // overwrites disk after the toggle already wrote `true`, silently
      // reverting the scroll setting. This is why loadDirectory must go
      // through update() instead of a read-then-save round trip.
      expect(onDisk['invert_vertical_scroll'], false);
    });

    test('a setting written by one update survives a later unrelated update', () async {
      final manager = ConfigManager(configFile);
      await manager.load();

      final first = manager.update((config) {
        config['invert_vertical_scroll'] = true;
        return config;
      });
      final second = manager.update((config) {
        config['last_visited_directory'] = '/tmp/somewhere';
        return config;
      });
      await Future.wait([first, second]);

      final onDisk = json.decode(await configFile.readAsString()) as Map<String, dynamic>;
      expect(onDisk['invert_vertical_scroll'], true);
      expect(onDisk['last_visited_directory'], '/tmp/somewhere');
    });
  });
}
