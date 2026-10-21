import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/models/directory_layout_issue.dart';
import 'package:file_tile/src/models/binding_map.dart';
import 'package:file_tile/src/repositories/desktop_repository.dart';
import 'package:file_tile/src/utils/os_file_clipboard.dart';
import 'package:file_tile/src/utils/terminal_launcher.dart';
import 'package:file_tile/src/utils/thumbnail_cache.dart';
import 'package:file_tile/src/utils/metadata_helper.dart';
import 'package:file_tile/src/viewmodels/desktop_viewmodel.dart';

import 'fake_desktop_repository.dart';

/// Polls [condition] until it's true, since the ViewModel drives its own
/// async work (loadDirectory, save-on-change) without exposing futures for
/// every side effect.
Future<void> _pumpUntil(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

TerminalLauncher _silentTerminalLauncher() {
  return TerminalLauncher(
    isLinux: true,
    isMacOS: false,
    isWindows: false,
    resolveCommand: (_) async => null,
    startProcess: (executable, arguments, {workingDirectory}) async {},
  );
}

TerminalLauncher _recordingTerminalLauncher({
  required List<String> availableIds,
  required List<TerminalInvocation> launches,
}) {
  return TerminalLauncher(
    isLinux: true,
    isMacOS: false,
    isWindows: false,
    resolveCommand: (cmd) async =>
        availableIds.contains(cmd) ? '/usr/bin/$cmd' : null,
    startProcess: (executable, arguments, {workingDirectory}) async {
      launches.add(TerminalInvocation(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory ?? '',
      ));
    },
  );
}

class _FakeOsFileClipboard implements OsFileClipboard {
  OsFileClipboardSnapshot? snapshot;

  @override
  Future<void> write(List<String> paths, {required bool isCut}) async {
    snapshot = OsFileClipboardSnapshot(paths: List.of(paths), isCut: isCut);
  }

  @override
  Future<OsFileClipboardSnapshot?> read() async => snapshot;

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}

Future<DesktopViewModel> _createInitialized(FakeDesktopRepository repo,
    {TerminalLauncher? terminalLauncher, OsFileClipboard? osClipboard}) async {
  final vm = DesktopViewModel(
    repository: repo,
    terminalLauncher: terminalLauncher ?? _silentTerminalLauncher(),
    osClipboard: osClipboard ?? NoOpOsFileClipboard(),
    thumbnailCache: ThumbnailCache(loader: (_) async => null),
  );
  await _pumpUntil(() => vm.isInitialized);
  return vm;
}

void main() {
  group('DesktopViewModel.loadDirectory', () {
    test(
        'restores positions from saved layout and grid-packs unpositioned entries',
        () async {
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

      final unpositioned = vm.nodes
          .where((n) => n.name != 'b.txt')
          .map((n) => n.position)
          .toSet();
      // Default NewElementPlacementConfig anchors at grid (col 1, row 1),
      // growing rightward, so the first two auto-placed positions are (0,0) and (80,0).
      expect(unpositioned, {const Offset(0, 0), const Offset(80, 0)});
    });

    test('first inbox placement orders untracked items by ascending recency',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(
          name: 'newest.txt',
          isDirectory: false,
          modified: DateTime.utc(2026, 3, 1),
        ),
        DesktopEntity(
          name: 'oldest-folder',
          isDirectory: true,
          modified: DateTime.utc(2018, 1, 1),
        ),
        DesktopEntity(
          name: 'middle.txt',
          isDirectory: false,
          modified: DateTime.utc(2022, 6, 1),
        ),
        DesktopEntity(
          name: 'tie-b.txt',
          isDirectory: false,
          modified: DateTime.utc(2022, 6, 1),
        ),
      ]);

      final vm = await _createInitialized(repo);

      Offset at(String name) =>
          vm.nodes.firstWhere((n) => n.name == name).position;
      // Oldest at the anchor, then along the row. Same timestamp breaks by name.
      expect(at('oldest-folder'), const Offset(0, 0));
      expect(at('middle.txt'), const Offset(80, 0));
      expect(at('tie-b.txt'), const Offset(160, 0));
      expect(at('newest.txt'), const Offset(240, 0));
    });

    test(
        'a later untracked batch fills free inbox cells by recency and leaves placed items',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(
          name: 'already.txt',
          isDirectory: false,
          modified: DateTime.utc(2010, 1, 1),
        ),
      ], layout: {
        'already.txt': {'x': 0.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      final existing = await repo.listEntities(repo.initialDirectory);
      repo.seedDirectory(repo.initialDirectory, [
        ...existing,
        DesktopEntity(
          name: 'newer.txt',
          isDirectory: false,
          modified: DateTime.utc(2025, 1, 1),
        ),
        DesktopEntity(
          name: 'older-new.txt',
          isDirectory: false,
          modified: DateTime.utc(2019, 5, 1),
        ),
      ]);

      await vm.loadDirectory(repo.initialDirectory, force: true);

      Offset at(String name) =>
          vm.nodes.firstWhere((n) => n.name == name).position;
      expect(at('already.txt'), const Offset(0, 0));
      expect(at('older-new.txt'), const Offset(80, 0));
      expect(at('newer.txt'), const Offset(160, 0));
    });
  });

  group('DesktopViewModel.createFile / createDirectory', () {
    test('adds a node at the requested grid position and persists it',
        () async {
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

    test('createSymlink adds a link node at the requested grid position',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      final vm = await _createInitialized(repo);

      await vm.createSymlink('shortcut', '/tmp/target',
          gridPosition: const Offset(80, 160));

      final link = vm.nodes.firstWhere((n) => n.name == 'shortcut');
      expect(link.isSymlink, true);
      expect(link.position, const Offset(80, 160));
      expect(
        repo.symlinkTargets[p.join(repo.initialDirectory, 'shortcut')],
        '/tmp/target',
      );

      final layout = await repo.readLayout(repo.initialDirectory);
      expect(layout['shortcut']['x'], 80.0);
      expect(layout['shortcut']['y'], 160.0);
    });

    test('createSymlink reports an error when the name is taken', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'shortcut', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);

      await vm.createSymlink('shortcut', '/tmp/target');

      expect(vm.lastError, "Couldn't create symlink shortcut");
      expect(repo.symlinkTargets, isEmpty);
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
    test('renames the node and carries its layout entry to the new name',
        () async {
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
      await _pumpUntil(
          () => !vm.isLoading && vm.currentDirectory == '/root/sub');
    });
  });

  group('DesktopViewModel settings persistence', () {
    test('invertVerticalScroll changes are saved to the repository config',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      final vm = await _createInitialized(repo);

      vm.invertVerticalScroll = true;

      await _pumpUntil(
          () => repo.configSnapshot['invert_vertical_scroll'] == true);
    });

    test('preferred_terminal is restored from config and saved on change',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      await repo.updateConfig((config) {
        config['preferred_terminal'] = 'konsole';
        return config;
      });
      final launches = <TerminalInvocation>[];
      final vm = await _createInitialized(
        repo,
        terminalLauncher: _recordingTerminalLauncher(
          availableIds: const ['kitty', 'konsole'],
          launches: launches,
        ),
      );

      expect(vm.preferredTerminalId, 'konsole');
      expect(vm.availableTerminals.map((t) => t.id), ['kitty', 'konsole']);

      vm.preferredTerminalId = 'kitty';
      await _pumpUntil(
          () => repo.configSnapshot['preferred_terminal'] == 'kitty');
    });

    test('bindings are restored from config and saved on rebind', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      await repo.updateConfig((config) {
        config['bindings'] = {
          'zoom': {'type': 'pointer', 'chord': 'ctrlScroll'},
          'panHorizontal': {'type': 'pointer', 'chord': 'scroll'},
        };
        return config;
      });
      final vm = await _createInitialized(repo);

      expect(vm.bindings[ControlAction.zoom].pointer, PointerChord.ctrlScroll);
      expect(vm.bindings[ControlAction.panHorizontal].pointer,
          PointerChord.scroll);

      vm.rebindControl(
        ControlAction.toggleSelect,
        const ControlBinding.pointer(PointerChord.shiftPrimaryClick),
      );
      await _pumpUntil(() {
        final stored = repo.configSnapshot['bindings'];
        if (stored is! Map) return false;
        final toggle = stored['toggleSelect'];
        return toggle is Map && toggle['chord'] == 'shiftPrimaryClick';
      });
      expect(vm.bindings[ControlAction.rangeSelect].pointer,
          PointerChord.ctrlPrimaryClick);
    });
  });

  group('DesktopViewModel.openInTerminal', () {
    test('opens a folder node at that folder path', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      final launches = <TerminalInvocation>[];
      final vm = await _createInitialized(
        repo,
        terminalLauncher: _recordingTerminalLauncher(
          availableIds: const ['kitty'],
          launches: launches,
        ),
      );

      final folder = vm.nodes.firstWhere((n) => n.name == 'sub');
      expect(vm.terminalDirectoryForNode(folder), '/root/sub');

      await vm.openInTerminal(
          workingDirectory: vm.terminalDirectoryForNode(folder));
      expect(launches, isNotEmpty);
      expect(launches.last.workingDirectory, '/root/sub');
      expect(launches.last.arguments, contains('/root/sub'));
    });

    test('openSelectedInTerminal ignores a selected file', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      final launches = <TerminalInvocation>[];
      final vm = await _createInitialized(
        repo,
        terminalLauncher: _recordingTerminalLauncher(
          availableIds: const ['kitty'],
          launches: launches,
        ),
      );
      vm.selectNode('notes.txt');
      await vm.performSelectAction(DesktopSelectAction.openInTerminal);
      expect(launches, isEmpty);
    });

    test('openSelectedInTerminal uses the first selected folder', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      final launches = <TerminalInvocation>[];
      final vm = await _createInitialized(
        repo,
        terminalLauncher: _recordingTerminalLauncher(
          availableIds: const ['kitty'],
          launches: launches,
        ),
      );
      vm.selectNode('sub');
      await vm.performSelectAction(DesktopSelectAction.openInTerminal);

      expect(launches.single.workingDirectory, '/root/sub');
    });

    test('sets lastError when no emulator is available', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      final vm = await _createInitialized(repo);

      await vm.openInTerminal();
      expect(vm.lastError, contains('terminal emulator'));
    });
  });

  group('DesktopViewModel error surfacing', () {
    test('a failed process launch sets lastError with a user-facing message',
        () async {
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

    test(
        'a layout permission error sets layoutIssue and does not queue lastError',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
      ]);
      repo.layoutIoError = FileSystemException(
        'Failed',
        '/root/file-tile.json',
        const OSError('Permission denied', 13),
      );

      final vm = await _createInitialized(repo);

      expect(vm.lastError, isNull);
      expect(vm.layoutIssue, isNotNull);
      expect(vm.layoutIssue!.kind, DirectoryLayoutIssueKind.permissionDenied);
      expect(vm.nodes.any((n) => n.name == 'a.txt'), isTrue);
      expect(repo.updateLayoutCount, 0);
    });

    test('a failed polled layout read does not set lastError or persist a wipe',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
      ], layout: {
        'a.txt': {'x': 80.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);
      final savedPosition =
          vm.nodes.firstWhere((n) => n.name == 'a.txt').position;

      repo.layoutIoError = FileSystemException(
        'Failed',
        '/root/file-tile.json',
        const OSError('Permission denied', 13),
      );
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
      ]);

      await vm.loadDirectory(repo.initialDirectory,
          addToHistory: false, force: true, isPolledRefresh: true);
      await vm.loadDirectory(repo.initialDirectory,
          addToHistory: false, force: true, isPolledRefresh: true);

      expect(vm.lastError, isNull);
      expect(vm.layoutIssue, isNotNull);
      expect(vm.nodes.firstWhere((n) => n.name == 'a.txt').position,
          savedPosition);
      expect(vm.nodes.any((n) => n.name == 'b.txt'), isTrue);
    });

    test('layoutIssue clears after navigating to a writable directory',
        () async {
      final repo = FakeDesktopRepository(initialDirectory: '/bad');
      repo.seedDirectory('/bad', [
        DesktopEntity(name: 'x.txt', isDirectory: false),
      ]);
      repo.seedDirectory('/good', [
        DesktopEntity(name: 'y.txt', isDirectory: false),
      ]);
      repo.layoutIoError = FileSystemException(
        'Failed',
        '/bad/file-tile.json',
        const OSError('Permission denied', 13),
      );
      repo.layoutIoErrorPath = '/bad';

      final vm = await _createInitialized(repo);
      expect(vm.layoutIssue, isNotNull);

      await vm.loadDirectory('/good');
      expect(vm.currentDirectory, '/good');
      expect(vm.layoutIssue, isNull);
      expect(vm.lastError, isNull);
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
      // Default NewElementPlacementConfig anchors at grid (col 1, row 1),
      // growing rightward, so the first two auto-placed positions are (0,0) and (80,0).
      expect(layout['file1.txt']['x'], 0.0);
      expect(layout['file1.txt']['y'], 0.0);
      expect(layout['file2.txt']['x'], 80.0);
      expect(layout['file2.txt']['y'], 0.0);
    });
  });

  group('DesktopViewModel clipboard', () {
    test(
        'copy then paste in the same folder creates a uniquely named duplicate',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      vm.selectNode('notes.txt');
      await vm.copySelection();

      await vm.paste();

      expect(vm.nodes.map((n) => n.name),
          containsAll(['notes.txt', 'notes (copy).txt']));
      expect(vm.clipboard, isNotNull);
    });

    test('cut then paste in the same folder moves the tile to the paste cell',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      vm.selectNode('notes.txt');
      await vm.cutSelection();
      final start = vm.nodes.firstWhere((n) => n.name == 'notes.txt').position;

      await vm.paste(at: const Offset(240, 160));

      expect(vm.nodes.where((n) => n.name == 'notes.txt'), hasLength(1));
      expect(vm.nodes.firstWhere((n) => n.name == 'notes.txt').position,
          const Offset(240, 160));
      expect(start, isNot(const Offset(240, 160)));
      expect(vm.clipboard, isNull);
    });

    test('copy then paste into another folder keeps the original name',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);
      vm.selectNode('notes.txt');
      await vm.copySelection();
      await vm.loadDirectory('/root/sub');
      await vm.paste();

      expect(vm.nodes.map((n) => n.name), contains('notes.txt'));
      expect(
          (await repo.listEntities(repo.initialDirectory))
              .map((e) => e.name)
              .toList(),
          contains('notes.txt'));
    });

    test('cut then paste into another folder moves the item', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);
      vm.selectNode('notes.txt');
      await vm.cutSelection();
      await vm.loadDirectory('/root/sub');
      await vm.paste();

      expect(vm.nodes.map((n) => n.name), contains('notes.txt'));
      expect(
          (await repo.listEntities(repo.initialDirectory))
              .any((e) => e.name == 'notes.txt'),
          isFalse);
      expect(vm.clipboard, isNull);
    });

    test('paste throws MoveConflictException when the name already exists',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      vm.selectNode('notes.txt');
      await vm.copySelection();
      await vm.loadDirectory('/root/sub');

      await expectLater(vm.paste(), throwsA(isA<MoveConflictException>()));
    });

    test('copy writes absolute paths to the OS clipboard', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      final os = _FakeOsFileClipboard();
      final vm = await _createInitialized(repo, osClipboard: os);
      vm.selectNode('notes.txt');
      await vm.copySelection();

      expect(os.snapshot, isNotNull);
      expect(os.snapshot!.isCut, isFalse);
      expect(os.snapshot!.paths, ['/root/notes.txt']);
    });

    test('paste uses OS clipboard files when the in-app clipboard is empty',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', []);
      final os = _FakeOsFileClipboard()
        ..snapshot = const OsFileClipboardSnapshot(
          paths: ['/root/notes.txt'],
          isCut: false,
        );
      final vm = await _createInitialized(repo, osClipboard: os);
      await vm.loadDirectory('/root/sub');
      expect(await vm.paste(), isTrue);
      expect(vm.nodes.map((n) => n.name), contains('notes.txt'));
      expect(
          (await repo.listEntities(repo.initialDirectory))
              .any((e) => e.name == 'notes.txt'),
          isTrue);
    });

    test('paste from an OS cut moves the files and clears the OS clipboard',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', []);
      final os = _FakeOsFileClipboard()
        ..snapshot = const OsFileClipboardSnapshot(
          paths: ['/root/notes.txt'],
          isCut: true,
        );
      final vm = await _createInitialized(repo, osClipboard: os);
      await vm.loadDirectory('/root/sub');
      expect(await vm.paste(), isTrue);
      expect(vm.nodes.map((n) => n.name), contains('notes.txt'));
      expect(
          (await repo.listEntities(repo.initialDirectory))
              .any((e) => e.name == 'notes.txt'),
          isFalse);
      expect(os.snapshot, isNull);
    });
  });

  group('DesktopViewModel importPaths', () {
    test('moves a file from another folder into the current directory',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', [
        DesktopEntity(name: 'photo.jpg', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);

      expect(
        await vm.importPaths(['/root/sub/photo.jpg'],
            isCut: true, at: const Offset(160, 80)),
        isTrue,
      );
      expect(vm.nodes.map((n) => n.name), contains('photo.jpg'));
      expect(vm.nodes.firstWhere((n) => n.name == 'photo.jpg').position,
          const Offset(160, 80));
      expect(
          (await repo.listEntities('/root/sub'))
              .any((e) => e.name == 'photo.jpg'),
          isFalse);
    });

    test('copies when isCut is false', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', [
        DesktopEntity(name: 'photo.jpg', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);

      expect(
        await vm.importPaths(['/root/sub/photo.jpg'], isCut: false),
        isTrue,
      );
      expect(vm.nodes.map((n) => n.name), contains('photo.jpg'));
      expect(
          (await repo.listEntities('/root/sub'))
              .any((e) => e.name == 'photo.jpg'),
          isTrue);
    });

    test('imports into a folder tile without navigating', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'here.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/elsewhere', [
        DesktopEntity(name: 'incoming.txt', isDirectory: false),
      ]);
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);

      expect(
        await vm.importPaths(['/elsewhere/incoming.txt'],
            isCut: true, destDir: '/root/sub'),
        isTrue,
      );
      expect(vm.currentDirectory, repo.initialDirectory);
      expect(vm.nodes.map((n) => n.name), containsAll(['here.txt', 'sub']));
      expect((await repo.listEntities('/root/sub')).map((e) => e.name),
          contains('incoming.txt'));
      expect((await repo.readLayout('/root/sub')).containsKey('incoming.txt'),
          isTrue);
    });

    test('throws MoveConflictException when the name already exists', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      repo.seedDirectory('/elsewhere', [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);

      await expectLater(
        vm.importPaths(['/elsewhere/notes.txt'], isCut: true),
        throwsA(isA<MoveConflictException>()),
      );
    });

    test('repositions every dragged tile and keeps their spacing', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
        DesktopEntity(name: 'c.txt', isDirectory: false),
      ], layout: {
        'a.txt': {'x': 0.0, 'y': 0.0},
        'b.txt': {'x': 160.0, 'y': 0.0},
        'c.txt': {'x': 0.0, 'y': 80.0},
      });
      final vm = await _createInitialized(repo);

      final decision = vm.resolveInAppCanvasDrop(
        paths: ['/root/a.txt', '/root/b.txt'],
        anchorPath: '/root/a.txt',
        dropCell: const Offset(80, 0),
        vacateSources: true,
      );
      expect(decision!.kind, InAppCanvasDropKind.reposition);
      expect(decision.placements['a.txt'], const Offset(80, 0));
      expect(decision.placements['b.txt'], const Offset(240, 0));

      expect(
        await vm.importPaths(
          ['/root/a.txt', '/root/b.txt'],
          isCut: true,
          placements: decision.placements,
        ),
        isTrue,
      );
      Offset at(String name) =>
          vm.nodes.firstWhere((n) => n.name == name).position;
      expect(at('a.txt'), const Offset(80, 0));
      expect(at('b.txt'), const Offset(240, 0));
      expect(at('c.txt'), const Offset(0, 80));
    });

    test('a move may land on a cell another dragged tile is leaving', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
      ], layout: {
        'a.txt': {'x': 0.0, 'y': 0.0},
        'b.txt': {'x': 80.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      final decision = vm.resolveInAppCanvasDrop(
        paths: ['/root/a.txt', '/root/b.txt'],
        anchorPath: '/root/a.txt',
        dropCell: const Offset(80, 0),
        vacateSources: true,
      );
      expect(decision!.kind, InAppCanvasDropKind.reposition);

      expect(
        await vm.importPaths(
          ['/root/a.txt', '/root/b.txt'],
          isCut: true,
          placements: decision.placements,
        ),
        isTrue,
      );
      Offset at(String name) =>
          vm.nodes.firstWhere((n) => n.name == name).position;
      expect(at('a.txt'), const Offset(80, 0));
      expect(at('b.txt'), const Offset(160, 0));
    });

    test('refuses the whole move when any target cell is occupied', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
        DesktopEntity(name: 'c.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ], layout: {
        'a.txt': {'x': 0.0, 'y': 0.0},
        'b.txt': {'x': 80.0, 'y': 0.0},
        'c.txt': {'x': 0.0, 'y': 80.0},
        'sub': {'x': 160.0, 'y': 80.0},
      });
      final vm = await _createInitialized(repo);
      final sub = vm.nodes.firstWhere((n) => n.name == 'sub');

      final ontoForeignFile = vm.resolveInAppCanvasDrop(
        paths: ['/root/a.txt', '/root/b.txt'],
        anchorPath: '/root/a.txt',
        dropCell: const Offset(0, 80),
        vacateSources: true,
      );
      expect(ontoForeignFile!.kind, InAppCanvasDropKind.blocked);

      final ontoOffCursorDirectory = vm.resolveInAppCanvasDrop(
        paths: ['/root/a.txt', '/root/b.txt'],
        anchorPath: '/root/a.txt',
        dropCell: const Offset(80, 80),
        vacateSources: true,
      );
      expect(ontoOffCursorDirectory!.kind, InAppCanvasDropKind.blocked);

      expect(
        await vm.importPaths(
          ['/root/a.txt', '/root/b.txt'],
          isCut: true,
          placements: const {
            'a.txt': Offset(0, 80),
            'b.txt': Offset(80, 80),
          },
        ),
        isFalse,
      );
      Offset at(String name) =>
          vm.nodes.firstWhere((n) => n.name == name).position;
      expect(at('a.txt'), const Offset(0, 0));
      expect(at('b.txt'), const Offset(80, 0));
      expect(at('c.txt'), const Offset(0, 80));
      expect(at('sub'), sub.position);
      expect(
        (await repo.listEntities('/root')).map((e) => e.name),
        containsAll(['a.txt', 'b.txt']),
      );
    });

    test('dropping the dragged tile on a directory moves the whole set',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
        DesktopEntity(name: 'c.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ], layout: {
        'a.txt': {'x': 0.0, 'y': 0.0},
        'b.txt': {'x': 80.0, 'y': 0.0},
        'c.txt': {'x': 160.0, 'y': 0.0},
        'sub': {'x': 0.0, 'y': 80.0},
      });
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);
      final sub = vm.nodes.firstWhere((n) => n.name == 'sub');

      final decision = vm.resolveInAppCanvasDrop(
        paths: ['/root/a.txt', '/root/b.txt'],
        anchorPath: '/root/a.txt',
        dropCell: sub.position,
        vacateSources: true,
        cursorNode: sub,
      );
      expect(decision!.kind, InAppCanvasDropKind.intoDirectory);
      expect(decision.directoryPath, '/root/sub');

      expect(
        await vm.importPaths(
          ['/root/a.txt', '/root/b.txt'],
          isCut: true,
          destDir: decision.directoryPath,
        ),
        isTrue,
      );
      expect(vm.nodes.map((n) => n.name), containsAll(['c.txt', 'sub']));
      expect(vm.nodes.map((n) => n.name), isNot(contains('a.txt')));
      expect(
        (await repo.listEntities('/root/sub')).map((e) => e.name),
        containsAll(['a.txt', 'b.txt']),
      );
    });

    test('a copy is refused when a landing cell is still occupied', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
      ], layout: {
        'a.txt': {'x': 0.0, 'y': 0.0},
        'b.txt': {'x': 80.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      final decision = vm.resolveInAppCanvasDrop(
        paths: ['/root/a.txt', '/root/b.txt'],
        anchorPath: '/root/a.txt',
        dropCell: const Offset(80, 0),
        vacateSources: false,
      );
      expect(decision!.kind, InAppCanvasDropKind.blocked);

      expect(
        await vm.importPaths(
          ['/root/a.txt', '/root/b.txt'],
          isCut: false,
          placements: const {
            'a.txt': Offset(80, 0),
            'b.txt': Offset(160, 0),
          },
        ),
        isFalse,
      );
      expect(vm.nodes.map((n) => n.name), ['a.txt', 'b.txt']);
    });

    test('a copy keeps spacing and leaves the originals in place', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
      ], layout: {
        'a.txt': {'x': 0.0, 'y': 0.0},
        'b.txt': {'x': 160.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      expect(
        await vm.importPaths(
          ['/root/a.txt', '/root/b.txt'],
          isCut: false,
          placements: const {
            'a.txt': Offset(0, 80),
            'b.txt': Offset(160, 80),
          },
        ),
        isTrue,
      );
      Offset at(String name) =>
          vm.nodes.firstWhere((n) => n.name == name).position;
      expect(at('a.txt'), const Offset(0, 0));
      expect(at('b.txt'), const Offset(160, 0));
      expect(at('a (copy).txt'), const Offset(0, 80));
      expect(at('b (copy).txt'), const Offset(160, 80));
    });

    test('finalizeExternalMove deletes leftovers and reloads', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'gone.txt', isDirectory: false),
        DesktopEntity(name: 'stays.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      await vm.finalizeExternalMove(['/root/gone.txt']);
      expect(vm.nodes.map((n) => n.name), ['stays.txt']);
    });
  });

  // Deferred: directory search.
  // group('DesktopViewModel search', () {
  //   test('filters the current listing by name without dropping other nodes',
  //       () async {
  //     final repo = FakeDesktopRepository();
  //     repo.seedDirectory(repo.initialDirectory, [
  //       DesktopEntity(name: 'alpha.txt', isDirectory: false),
  //       DesktopEntity(name: 'beta.txt', isDirectory: false),
  //     ]);
  //     final vm = await _createInitialized(repo);
  //     vm.setSearchQuery('alp');
  //
  //     expect(vm.visibleNodes.map((n) => n.name), ['alpha.txt']);
  //     expect(
  //         vm.nodes.map((n) => n.name), containsAll(['alpha.txt', 'beta.txt']));
  //     expect(vm.isSearchMatch('alpha.txt'), isTrue);
  //   });
  //
  //   test(
  //       'nested search lists matches under subfolders and skips unlistable dirs',
  //       () async {
  //     final repo = FakeDesktopRepository();
  //     repo.seedDirectory(repo.initialDirectory, [
  //       DesktopEntity(name: 'visible.txt', isDirectory: false),
  //       DesktopEntity(name: 'ok', isDirectory: true),
  //       DesktopEntity(name: 'secret', isDirectory: true),
  //     ]);
  //     repo.seedDirectory('/root/ok', [
  //       DesktopEntity(name: 'needle.txt', isDirectory: false),
  //     ]);
  //     repo.seedDirectory('/root/secret', [
  //       DesktopEntity(name: 'needle.txt', isDirectory: false),
  //     ]);
  //     repo.listEntitiesError = Exception('permission denied');
  //     repo.listEntitiesErrorPath = '/root/secret';
  //
  //     final vm = await _createInitialized(repo);
  //     vm.setSearchQuery('needle');
  //     vm.setSearchIncludeNested(true);
  //     await _pumpUntil(
  //         () => !vm.nestedSearchInProgress && vm.nestedSearchHits.isNotEmpty);
  //
  //     expect(vm.nestedSearchHits.map((h) => h.relativePath), ['ok/needle.txt']);
  //     expect(vm.lastError, isNull);
  //   });
  // });

  group('DesktopViewModel layout file', () {
    test('can reposition file-tile.json on the canvas without moving it',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: MetadataManager.fileName, isDirectory: false),
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ], layout: {
        MetadataManager.fileName: {'x': 0.0, 'y': 0.0},
        'notes.txt': {'x': 160.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      vm.startDrag({MetadataManager.fileName});
      vm.updateNodePosition(MetadataManager.fileName, const Offset(80, 80));
      await vm.completeOrRevertDrag({MetadataManager.fileName});

      expect(
        vm.nodes.firstWhere((n) => n.name == MetadataManager.fileName).position,
        const Offset(80, 80),
      );
      expect(
        (await repo.readLayout(repo.initialDirectory))[MetadataManager.fileName]
            ['x'],
        80.0,
      );
      expect(
        (await repo.listEntities(repo.initialDirectory))
            .any((e) => e.name == MetadataManager.fileName),
        isTrue,
      );
    });

    test('copy and move skip file-tile.json', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: MetadataManager.fileName, isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);
      vm.selectNode(MetadataManager.fileName);

      await vm.copySelection();
      expect(vm.clipboard, isNull);

      await vm.moveNodesToDirectory({MetadataManager.fileName}, '/root/sub');
      expect(
        (await repo.listEntities(repo.initialDirectory))
            .any((e) => e.name == MetadataManager.fileName),
        isTrue,
      );
      expect(
        (await repo.listEntities('/root/sub'))
            .any((e) => e.name == MetadataManager.fileName),
        isFalse,
      );
    });
  });

  group('DesktopViewModel undo', () {
    test('undo and redo a drag into another directory', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ], layout: {
        'notes.txt': {'x': 80.0, 'y': 160.0, 'color': 0xFF00FF00},
      });
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);

      await vm.moveNodesToDirectory({'notes.txt'}, '/root/sub');
      expect(vm.nodes.any((n) => n.name == 'notes.txt'), isFalse);
      expect(vm.canUndo, isTrue);

      await vm.undo();
      final restored = vm.nodes.firstWhere((n) => n.name == 'notes.txt');
      expect(restored.position, const Offset(80, 160));
      expect(restored.color, const Color(0xFF00FF00));
      expect(
        (await repo.listEntities('/root/sub')).any((e) => e.name == 'notes.txt'),
        isFalse,
      );
      expect(vm.canRedo, isTrue);

      await vm.redo();
      expect(vm.nodes.any((n) => n.name == 'notes.txt'), isFalse);
      final dest = await repo.readLayout('/root/sub');
      expect(dest['notes.txt']['color'], 0xFF00FF00);
      expect(vm.canUndo, isTrue);
    });

    test('undo of a folder drop restores the original cell', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'photo.jpg', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ], layout: {
        'photo.jpg': {'x': 160.0, 'y': 80.0},
      });
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);

      expect(
        await vm.importPaths(
          [p.join(repo.initialDirectory, 'photo.jpg')],
          isCut: true,
          destDir: '/root/sub',
        ),
        isTrue,
      );
      expect(vm.currentDirectory, repo.initialDirectory);

      await vm.undo();
      expect(
        vm.nodes.firstWhere((n) => n.name == 'photo.jpg').position,
        const Offset(160, 80),
      );
      expect(
        (await repo.listEntities('/root/sub')).any((e) => e.name == 'photo.jpg'),
        isFalse,
      );
    });

    test('undo refuses to overwrite a name that appeared in the source',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: 'sub', isDirectory: true),
      ]);
      repo.seedDirectory('/root/sub', []);
      final vm = await _createInitialized(repo);
      await vm.moveNodesToDirectory({'notes.txt'}, '/root/sub');
      await repo.createFile(p.join(repo.initialDirectory, 'notes.txt'));

      await vm.undo();

      expect(vm.lastError, "Can't undo — a file with that name is already there");
      expect(vm.canUndo, isTrue);
      expect(
        (await repo.listEntities('/root/sub')).any((e) => e.name == 'notes.txt'),
        isTrue,
      );
    });

    test('create, delete, and rename undo and redo', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'old.txt', isDirectory: false),
      ], layout: {
        'old.txt': {'x': 0.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      await vm.createFile('new.txt', gridPosition: const Offset(160, 80));
      await vm.undo();
      expect(vm.nodes.any((n) => n.name == 'new.txt'), isFalse);
      await vm.redo();
      expect(
        vm.nodes.firstWhere((n) => n.name == 'new.txt').position,
        const Offset(160, 80),
      );

      await vm.deleteNode('new.txt');
      expect(vm.nodes.any((n) => n.name == 'new.txt'), isFalse);
      await vm.undo();
      expect(
        vm.nodes.firstWhere((n) => n.name == 'new.txt').position,
        const Offset(160, 80),
      );

      await vm.renameNode('old.txt', 'renamed.txt');
      await vm.undo();
      expect(vm.nodes.any((n) => n.name == 'old.txt'), isTrue);
      await vm.redo();
      expect(vm.nodes.any((n) => n.name == 'renamed.txt'), isTrue);
    });

    test('deleting a selection is a single undo', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'a.txt', isDirectory: false),
        DesktopEntity(name: 'b.txt', isDirectory: false),
        DesktopEntity(name: 'c.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      vm.selectNode('a.txt');
      vm.selectNode('b.txt', multiSelect: true);

      await vm.performSelectAction(DesktopSelectAction.delete);
      expect(vm.nodes.map((n) => n.name), ['c.txt']);

      await vm.undo();
      expect(vm.nodes.map((n) => n.name).toSet(), {'a.txt', 'b.txt', 'c.txt'});
      expect(vm.canUndo, isFalse);
    });

    test('undo of a copy trashes the new file and leaves the original',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      vm.selectNode('notes.txt');
      await vm.copySelection();
      await vm.paste();
      expect(vm.nodes.map((n) => n.name),
          containsAll(['notes.txt', 'notes (copy).txt']));

      await vm.undo();
      expect(vm.nodes.map((n) => n.name), ['notes.txt']);
      await vm.redo();
      expect(vm.nodes.map((n) => n.name),
          containsAll(['notes.txt', 'notes (copy).txt']));
    });

    test('undo of a same-folder cut paste restores the old cell', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
      ], layout: {
        'notes.txt': {'x': 0.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);
      vm.selectNode('notes.txt');
      await vm.cutSelection();
      await vm.paste(at: const Offset(240, 160));
      expect(
        vm.nodes.firstWhere((n) => n.name == 'notes.txt').position,
        const Offset(240, 160),
      );

      await vm.undo();
      expect(
        vm.nodes.firstWhere((n) => n.name == 'notes.txt').position,
        const Offset(0, 0),
      );
    });

    test('color and canvas position changes undo', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'notes.txt', isDirectory: false),
        DesktopEntity(name: MetadataManager.fileName, isDirectory: false),
      ], layout: {
        'notes.txt': {'x': 0.0, 'y': 0.0},
        MetadataManager.fileName: {'x': 80.0, 'y': 0.0},
      });
      final vm = await _createInitialized(repo);

      await vm.updateNodeColor('notes.txt', const Color(0xFFFF0000));
      await vm.undo();
      expect(vm.nodes.firstWhere((n) => n.name == 'notes.txt').color, isNull);
      await vm.redo();
      expect(
        vm.nodes.firstWhere((n) => n.name == 'notes.txt').color,
        const Color(0xFFFF0000),
      );

      vm.startDrag({MetadataManager.fileName});
      vm.updateNodePosition(MetadataManager.fileName, const Offset(80, 80));
      await vm.completeOrRevertDrag({MetadataManager.fileName});
      await vm.undo();
      expect(
        vm.nodes.firstWhere((n) => n.name == MetadataManager.fileName).position,
        const Offset(80, 0),
      );
    });

    test('a new edit drops redo', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, []);
      final vm = await _createInitialized(repo);
      await vm.createFile('a.txt');
      await vm.undo();
      expect(vm.canRedo, isTrue);

      await vm.createFile('b.txt');
      expect(vm.canRedo, isFalse);
      await vm.redo();
      expect(vm.nodes.any((n) => n.name == 'a.txt'), isFalse);
      expect(vm.nodes.any((n) => n.name == 'b.txt'), isTrue);
    });

    test('an external drag-out can be undone', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'gone.txt', isDirectory: false),
      ], layout: {
        'gone.txt': {'x': 80.0, 'y': 160.0, 'color': 0xFF112233},
      });
      final vm = await _createInitialized(repo);
      await vm.finalizeExternalMove([p.join(repo.initialDirectory, 'gone.txt')]);
      expect(vm.nodes, isEmpty);
      expect(vm.canUndo, isTrue);

      await vm.undo();
      final restored = vm.nodes.firstWhere((n) => n.name == 'gone.txt');
      expect(restored.position, const Offset(80, 160));
      expect(restored.color, const Color(0xFF112233));
      expect(vm.canRedo, isTrue);

      await vm.redo();
      expect(vm.nodes, isEmpty);
      expect(vm.canUndo, isTrue);
    });

    test('an external move of a file the other app already took is not an undo',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'stays.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      await vm.finalizeExternalMove(
          [p.join(repo.initialDirectory, 'missing.txt')]);
      expect(vm.nodes.map((n) => n.name), ['stays.txt']);
      expect(vm.canUndo, isFalse);
      expect(vm.lastError, isNull);
    });

    test('an external move can undo a file the other app already removed',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'gone.txt', isDirectory: false),
      ], layout: {
        'gone.txt': {'x': 80.0, 'y': 160.0},
      });
      final vm = await _createInitialized(repo);
      final path = p.join(repo.initialDirectory, 'gone.txt');
      await repo.delete(path);
      var released = false;

      await vm.finalizeExternalMove(
        [path],
        restoreTaken: (original) async {
          await repo.createFile(original);
          return true;
        },
        releaseUnused: () async {
          released = true;
        },
      );

      expect(vm.nodes, isEmpty);
      expect(vm.canUndo, isTrue);
      expect(released, isTrue);

      await vm.undo();
      expect(
        vm.nodes.firstWhere((n) => n.name == 'gone.txt').position,
        const Offset(80, 160),
      );
    });

    test('a non-move drop puts a taken file back and does not trash it',
        () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'gone.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      final path = p.join(repo.initialDirectory, 'gone.txt');
      await repo.delete(path);

      await vm.finalizeExternalMove(
        [path],
        deleteIfPresent: false,
        restoreTaken: (original) async {
          await repo.createFile(original);
          return true;
        },
      );

      expect(vm.nodes.any((n) => n.name == 'gone.txt'), isTrue);
      expect(vm.canUndo, isFalse);
    });

    test('a non-move drop leaves a file that is still there', () async {
      final repo = FakeDesktopRepository();
      repo.seedDirectory(repo.initialDirectory, [
        DesktopEntity(name: 'stays.txt', isDirectory: false),
      ]);
      final vm = await _createInitialized(repo);
      var released = false;
      await vm.finalizeExternalMove(
        [p.join(repo.initialDirectory, 'stays.txt')],
        deleteIfPresent: false,
        releaseUnused: () async {
          released = true;
        },
      );
      expect(vm.nodes.map((n) => n.name), ['stays.txt']);
      expect(vm.canUndo, isFalse);
      expect(released, isTrue);
    });
  });
}
