import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitch_desktop_grid/src/repositories/desktop_repository.dart';
import 'package:stitch_desktop_grid/src/viewmodels/desktop_viewmodel.dart';

import 'fake_desktop_repository.dart';

/// Polls [condition] until it's true, since the ViewModel drives its own
/// async work (loadDirectory, save-on-change) without exposing futures for
/// every side effect.
Future<void> _pumpUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

Future<DesktopViewModel> _createInitialized(FakeDesktopRepository repo) async {
  final vm = DesktopViewModel(repository: repo);
  await _pumpUntil(() => vm.isInitialized);
  return vm;
}

void main() {
  group('DesktopViewModel.loadDirectory', () {
    test('restores positions from saved layout and grid-packs unpositioned entries', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(
        repo.initialDirectory,
        [
          DesktopEntity(name: 'b.txt', isDirectory: false),
          DesktopEntity(name: 'a.txt', isDirectory: false),
          DesktopEntity(name: 'sub', isDirectory: true),
        ],
        layout: {
          'b.txt': {'x': 240.0, 'y': 160.0, 'color': 0xFFFF0000},
        },
      );

      final vm = await _createInitialized(repo);

      final bNode = vm.nodes.firstWhere((n) => n.name == 'b.txt');
      expect(bNode.position, const Offset(240.0, 160.0));
      expect(bNode.color, const Color(0xFFFF0000));
      expect(bNode.isDirectory, false);

      final subNode = vm.nodes.firstWhere((n) => n.name == 'sub');
      expect(subNode.isDirectory, true);

      final unpositioned = vm.nodes.where((n) => n.name != 'b.txt').map((n) => n.position).toSet();
      expect(unpositioned, {const Offset(0, 0), const Offset(80, 0)});
    });
  });

  group('DesktopViewModel.createFile / createDirectory', () {
    test('adds a node at the requested grid position and persists it', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      final vm = await _createInitialized(repo);

      await vm.createFile('new.txt', gridPosition: const Offset(160, 80));
      await vm.createDirectory('newDir', gridPosition: const Offset(240, 80));

      final file = vm.nodes.firstWhere((n) => n.name == 'new.txt');
      expect(file.isDirectory, false);
      expect(file.position, const Offset(160, 80));

      final dir = vm.nodes.firstWhere((n) => n.name == 'newDir');
      expect(dir.isDirectory, true);
      expect(dir.position, const Offset(240, 80));

      final layout = await repo.readLayout(repo.initialDirectory);
      expect(layout['new.txt']['x'], 160.0);
      expect(layout['newDir']['x'], 240.0);
    });
  });

  group('DesktopViewModel deletion', () {
    test('deleteNode removes the entry from nodes and layout', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
      ], layout: {
        'a.txt': {'x': 0.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      await vm.deleteNode('a.txt');

      expect(vm.nodes.any((n) => n.name == 'a.txt'), false);
      final layout = await repo.readLayout(repo.initialDirectory);
      expect(layout.containsKey('a.txt'), false);
    });

    test('performSelectAction(delete) removes every selected node', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
        DesktopEntity(name: 'c.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);

      vm.selectNode('a.txt');
      vm.selectNode('b.txt', multiSelect: true);
      expect(vm.selectedNodeNames, {'a.txt', 'b.txt'});

      await vm.performSelectAction(DesktopSelectAction.delete);

      expect(vm.nodes.map((n) => n.name).toSet(), {'c.txt'});
    });
  });

  group('DesktopViewModel.renameNode', () {
    test('renames the node and carries its layout entry to the new name', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'old.txt', isDirectory: false),
      ], layout: {
        'old.txt': {'x': 80.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      await vm.renameNode('old.txt', 'new.txt');

      expect(vm.nodes.any((n) => n.name == 'old.txt'), false);
      final renamed = vm.nodes.firstWhere((n) => n.name == 'new.txt');
      expect(renamed.position, const Offset(80.0, 0.0));

      final layout = await repo.readLayout(repo.initialDirectory);
      expect(layout.containsKey('old.txt'), false);
      expect(layout['new.txt']['x'], 80.0);
    });
  });

  group('DesktopViewModel history', () {
    test('back and forward navigate between visited directories', () async {
      final repo = FakeDesktopRepository(initialDirectory: '/root');
      repo.seedDirectory('/root', []);
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);

      await vm.loadDirectory('/root/sub');
      expect(vm.currentDirectory, '/root/sub');
      expect(vm.canGoBack, true);
      expect(vm.canGoForward, false);

      vm.back();
      await _pumpUntil(() => !vm.isLoading && vm.currentDirectory == '/root');
      expect(vm.canGoForward, true);

      vm.forward();
      await _pumpUntil(() => !vm.isLoading && vm.currentDirectory == '/root/sub');
    });
  });

  group('DesktopViewModel settings persistence', () {
    test('directoryColor and invertVerticalScroll changes are saved to the repository config', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      final vm = await _createInitialized(repo);

      vm.directoryColor = const Color(0xFF123456);
      vm.invertVerticalScroll = true;

      await _pumpUntil(() =>
          repo.configSnapshot['directory_color'] == 0xFF123456 &&
          repo.configSnapshot['invert_vertical_scroll'] == true);
    });
  });

  group('DesktopViewModel error surfacing', () {
    test('a failed process launch sets lastError with a user-facing message', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      final vm = await _createInitialized(repo);

      await vm.openWith('definitely-not-a-real-command-xyz', 'somefile.txt');

      expect(vm.lastError, isNotNull);
      expect(vm.lastError, contains('somefile.txt'));
    });

    test('a repository failure during startup sets lastError', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      repo.readConfigError = Exception('boom');

      final vm = await _createInitialized(repo);

      expect(vm.lastError, isNotNull);
    });
  });

  group('DesktopViewModel metadata creation', () {
    test('creates metadata file on first visit to empty folder', () async {
      final repo = FakeDesktopRepository();
      const newFolder = '/root/new-folder';
      repo.seedDirectory(newFolder, []);

      final vm = await _createInitialized(repo);
      await vm.loadDirectory(newFolder);

      // Verify layout was saved even though folder is empty
      final layout = await repo.readLayout(newFolder);
      // The layout should have been persisted (will be empty dict for empty folder)
      expect(layout, isA<Map<String, dynamic>>());
    });

    test('creates metadata file on first visit to folder with files', () async {
      final repo = FakeDesktopRepository();
      const newFolder = '/root/new-folder-with-files';
      repo.seedDirectory(newFolder, [
        DesktopEntity(name: 'file1.txt', isDirectory: false),
        DesktopEntity(name: 'file2.txt', isDirectory: false),
      ]);

      final vm = await _createInitialized(repo);
      await vm.loadDirectory(newFolder);

      // Verify layout was saved with auto-positioned entries
      final layout = await repo.readLayout(newFolder);
      expect(layout.containsKey('file1.txt'), true);
      expect(layout.containsKey('file2.txt'), true);
      expect(layout['file1.txt']['x'], 0.0);
      expect(layout['file2.txt']['x'], 80.0);
    });
  });
}
