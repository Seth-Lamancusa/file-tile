import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../controllers/selection_controller.dart';
import '../models/new_element_placement_config.dart';
import '../models/binding_map.dart';
import '../models/directory_layout_issue.dart';
import '../models/metadata_backend.dart';
import '../repositories/desktop_repository.dart';
import '../repositories/file_system_desktop_repository.dart';
import '../utils/copy_names.dart';
import '../utils/coordinate_space.dart';
import '../utils/grid_position.dart';
import '../utils/io_errors.dart';
import '../utils/metadata_helper.dart';
import '../utils/os_file_clipboard.dart';
import '../utils/terminal_launcher.dart';
import '../utils/thumbnail_cache.dart';

/// Actions that can be performed on selected nodes.
/// This is the single source of truth for select actions in the desktop view.
enum DesktopSelectAction {
  delete,
  openInTerminal,
  copy,
  cut,
}

/// Exception thrown when moving nodes results in naming conflicts.
class MoveConflictException implements Exception {
  final List<String> conflictingNames;
  final String targetPath;
  final List<String> attemptedNames;

  MoveConflictException({
    required this.conflictingNames,
    required this.targetPath,
    this.attemptedNames = const [],
  });

  @override
  String toString() =>
      'MoveConflictException: ${conflictingNames.join(", ")} already exist in target directory';
}

/// Sentinel used by [DesktopNode.copyWith] to distinguish "leave color
/// unchanged" from "set color to null".
const _unset = Object();

class DesktopClipboard {
  final String sourceDirectory;
  final List<String> names;
  final bool isCut;

  const DesktopClipboard({
    required this.sourceDirectory,
    required this.names,
    required this.isCut,
  });
}

// Deferred: directory search (filter + nested walk).
// class NestedSearchHit {
//   final String path;
//   final String relativePath;
//   final bool isDirectory;
//
//   const NestedSearchHit({
//     required this.path,
//     required this.relativePath,
//     required this.isDirectory,
//   });
//
//   String get name => p.basename(path);
// }

class DesktopNode {
  final String name;
  final bool isDirectory;
  final bool isSymlink;
  final Offset position;
  final Color? color;

  const DesktopNode({
    required this.name,
    required this.isDirectory,
    this.isSymlink = false,
    this.position = Offset.zero,
    this.color,
  });

  DesktopNode copyWith({Offset? position, Object? color = _unset}) {
    return DesktopNode(
      name: name,
      isDirectory: isDirectory,
      isSymlink: isSymlink,
      position: position ?? this.position,
      color: identical(color, _unset) ? this.color : color as Color?,
    );
  }

  Map<String, dynamic> toJson() => {
        'x': position.dx,
        'y': position.dy,
        if (color != null) 'color': color!.toARGB32(),
      };
}

class DesktopViewModel extends ChangeNotifier {
  final DesktopRepository _repository;
  final SelectionController _selectionController = SelectionController();
  late String _currentDirectory;
  List<DesktopNode> _nodes = [];
  bool _isLoading = false;
  String? _lastError;
  final Map<String, DirectoryLayoutIssue> _layoutIssuesByPath = {};
  bool _viewStateSaveFailed = false;
  NewElementPlacementConfig _newElementPlacementConfig =
      NewElementPlacementConfig.defaultConfig();

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _initialized = false;
  bool _switchingMetadataBackend = false;

  bool _invertVerticalScroll = false;
  bool _invertHorizontalScroll = false;
  ThemeMode _themeMode = ThemeMode.dark;
  BindingMap _bindings = BindingMap.defaults;
  MetadataBackend _metadataBackend = MetadataBackend.json;
  final ThumbnailCache thumbnailCache;

  bool get invertVerticalScroll => _invertVerticalScroll;
  bool get invertHorizontalScroll => _invertHorizontalScroll;
  ThemeMode get themeMode => _themeMode;
  BindingMap get bindings => _bindings;
  MetadataBackend get metadataBackend => _metadataBackend;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Color get directoryColor =>
      isDarkMode ? const Color(0xFFEBC351) : const Color(0xFFF3C258);
  Color get fileColor =>
      isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF2196F3);

  final List<String> _history = [];
  final List<String> _forwardHistory = [];

  // Drag state for collision detection and revert on collision
  final Map<String, Offset> _dragStartPositions = {};

  // Use GridConfig.gridCellSize instead; kept for backwards compatibility
  static const double gridSize = GridConfig.gridCellSize;

  final Map<String, bool> _availableApps = {};
  Map<String, bool> get availableApps => _availableApps;

  // Polling for directory changes
  Timer? _refreshTimer;
  Set<String> _lastPolledEntityNames = {};
  bool _pollInFlight = false;

  // True while the user is actively dragging a node, panning the canvas, or
  // drawing a selection box. Polling is suspended for the whole gesture so a
  // background reload can never clobber in-progress, unsaved UI state.
  bool _isInteracting = false;

  // Every disk-touching operation (load/create/delete/rename/move/poll) runs
  // through this chain so at most one is ever in flight. A newer operation
  // simply awaits the previous one instead of racing it - no request tokens
  // or cancellation needed.
  Future<void> _operationChain = Future.value();

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = _operationChain.then((_) => operation());
    _operationChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  final List<Map<String, String>> _appRegistry = [
    {'name': 'VS Code', 'cmd': 'code', 'icon': 'code'},
    {'name': 'Cursor', 'cmd': 'cursor', 'icon': 'terminal'},
    {'name': 'Sublime', 'cmd': 'subl', 'icon': 'edit'},
    {'name': 'Nautilus', 'cmd': 'nautilus', 'icon': 'folder_open'},
  ];
  List<Map<String, String>> get appRegistry => _appRegistry;

  final TerminalLauncher _terminalLauncher;
  final OsFileClipboard _osClipboard;
  List<TerminalApp> _availableTerminals = [];
  String? _preferredTerminalId;

  List<TerminalApp> get availableTerminals =>
      List.unmodifiable(_availableTerminals);
  String? get preferredTerminalId => _preferredTerminalId;

  set preferredTerminalId(String? value) {
    if (_preferredTerminalId == value) return;
    _preferredTerminalId = value;
    notifyListeners();
    _saveGlobalConfig();
  }

  DesktopClipboard? _clipboard;
  DesktopClipboard? get clipboard => _clipboard;
  bool get canPaste => true;

  // Deferred: directory search.
  // String _searchQuery = '';
  // bool _searchIncludeNested = false;
  // int _searchEpoch = 0;
  // List<NestedSearchHit> _nestedHits = [];
  // bool _nestedSearchInProgress = false;
  //
  // String get searchQuery => _searchQuery;
  // bool get searchIncludeNested => _searchIncludeNested;
  // List<NestedSearchHit> get nestedSearchHits => List.unmodifiable(_nestedHits);
  // bool get nestedSearchInProgress => _nestedSearchInProgress;
  //
  // List<DesktopNode> get visibleNodes {
  //   final q = _searchQuery.trim().toLowerCase();
  //   if (q.isEmpty) return _nodes;
  //   return _nodes
  //       .where((n) => n.name.toLowerCase().contains(q))
  //       .toList(growable: false);
  // }
  //
  // bool isSearchMatch(String name) {
  //   final q = _searchQuery.trim().toLowerCase();
  //   return q.isNotEmpty && name.toLowerCase().contains(q);
  // }

  bool isCutPending(String name) {
    final clip = _clipboard;
    return clip != null &&
        clip.isCut &&
        clip.sourceDirectory == _currentDirectory &&
        clip.names.contains(name);
  }

  String get currentDirectory => _currentDirectory;
  List<DesktopNode> get nodes => _nodes;
  NewElementPlacementConfig get newElementPlacementConfig =>
      _newElementPlacementConfig;

  /// Nodes in render order, with any currently-dragged nodes moved to the
  /// end so they render on top of everything else in the Stack.
  List<DesktopNode> get orderedNodes {
    final source = _nodes;
    if (_dragStartPositions.isEmpty) return source;
    final dragging = _dragStartPositions.keys.toSet();
    final notDragging = source.where((n) => !dragging.contains(n.name));
    final draggingNodes = source.where((n) => dragging.contains(n.name));
    return [...notDragging, ...draggingNodes];
  }

  bool get isLoading => _isLoading;
  bool get isInitialized => _initialized;
  bool get isSwitchingMetadataBackend => _switchingMetadataBackend;
  String? get lastError => _lastError;
  DirectoryLayoutIssue? get layoutIssue =>
      _layoutIssuesByPath[_currentDirectory];
  double get scale => _scale;
  Offset get offset => _offset;
  Set<String> get selectedNodeNames => _selectionController.selected;
  bool isNodeSelected(String nodeName) =>
      _selectionController.isSelected(nodeName);
  SelectionController get selectionController => _selectionController;

  /// Coordinate space converter (handles all screen ↔ logical conversions).
  CoordinateSpace get coords =>
      CoordinateSpace(scale: _scale, panOffset: _offset);

  set invertVerticalScroll(bool value) {
    if (_invertVerticalScroll != value) {
      _invertVerticalScroll = value;
      notifyListeners();
      _saveGlobalConfig();
    }
  }

  set invertHorizontalScroll(bool value) {
    if (_invertHorizontalScroll != value) {
      _invertHorizontalScroll = value;
      notifyListeners();
      _saveGlobalConfig();
    }
  }

  set isDarkMode(bool value) {
    final mode = value ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
      _saveGlobalConfig();
    }
  }

  void rebindControl(ControlAction action, ControlBinding binding) {
    if (_bindings[action] == binding) return;
    _bindings = _bindings.rebind(action, binding);
    notifyListeners();
    _saveGlobalConfig();
  }

  void resetBindings() {
    _bindings = BindingMap.defaults;
    notifyListeners();
    _saveGlobalConfig();
  }

  Future<void> setMetadataBackend(MetadataBackend backend) {
    if (_metadataBackend == backend || _switchingMetadataBackend) {
      return Future.value();
    }
    _switchingMetadataBackend = true;
    notifyListeners();
    return _runExclusive(() async {
      try {
        await _repository.setMetadataBackend(backend);
        _metadataBackend = backend;
        await _loadDirectoryImpl(_currentDirectory,
            addToHistory: false, force: true);
      } catch (e) {
        debugPrint('Failed to switch layout backend: $e');
        _setError("Couldn't switch layout storage");
      } finally {
        _switchingMetadataBackend = false;
        notifyListeners();
      }
    });
  }

  bool _layoutIoBlocked(String path) {
    return _layoutIssuesByPath[path]?.blocksLayoutIo == true;
  }

  bool get canGoBack => _history.isNotEmpty;
  bool get canGoForward => _forwardHistory.isNotEmpty;

  DesktopViewModel({
    DesktopRepository? repository,
    TerminalLauncher? terminalLauncher,
    OsFileClipboard? osClipboard,
    ThumbnailCache? thumbnailCache,
  })  : _repository = repository ?? FileSystemDesktopRepository(),
        _terminalLauncher = terminalLauncher ?? TerminalLauncher(),
        _osClipboard = osClipboard ?? SuperOsFileClipboard(),
        thumbnailCache = thumbnailCache ?? ThumbnailCache() {
    _currentDirectory = _repository.initialDirectory;
    _selectionController.addListener(_onSelectionChanged);
    this.thumbnailCache.addListener(_onThumbnailsChanged);
    _init();
  }

  void _onSelectionChanged() {
    notifyListeners();
  }

  void _onThumbnailsChanged() {
    notifyListeners();
  }

  void _setError(String message) {
    if (_lastError == message) return;
    _lastError = message;
    notifyListeners();
  }

  /// Call after displaying [lastError] so it isn't shown again.
  void clearError() {
    _lastError = null;
  }

  void _setLayoutIssue(String path, Object error) {
    final issue = DirectoryLayoutIssue(
      path: path,
      kind: classifyLayoutIoError(error),
    );
    if (_layoutIssuesByPath[path] == issue) return;
    _layoutIssuesByPath[path] = issue;
    notifyListeners();
  }

  void _clearLayoutIssueFor(String path) {
    if (_layoutIssuesByPath.remove(path) != null) {
      notifyListeners();
    }
  }

  Future<void> _checkAppAvailability() async {
    for (var app in _appRegistry) {
      final cmd = app['cmd']!;
      try {
        final result = await Process.run('which', [cmd]);
        _availableApps[cmd] = result.exitCode == 0;
      } catch (_) {
        _availableApps[cmd] = false;
      }
    }
    notifyListeners();
  }

  Future<void> openWith(String cmd, String fileName) async {
    final path = p.join(_currentDirectory, fileName);
    try {
      await Process.start(cmd, [path], workingDirectory: _currentDirectory);
    } catch (e) {
      debugPrint("Failed to open with $cmd: $e");
      _setError("Couldn't open $fileName with $cmd");
    }
  }

  Future<void> openSystemDefault(String fileName) async {
    final path = p.join(_currentDirectory, fileName);
    try {
      await Process.run('xdg-open', [path],
          workingDirectory: _currentDirectory);
    } catch (e) {
      debugPrint("Failed to open with xdg-open: $e");
      _setError("Couldn't open $fileName");
    }
  }

  Future<void> _init() async {
    await _checkAppAvailability();
    Map<String, dynamic> config = {};
    try {
      config = await _repository.readConfig();
    } catch (e) {
      debugPrint('Error reading config: $e');
      _setError("Couldn't read saved settings");
    }

    _invertVerticalScroll = config['invert_vertical_scroll'] as bool? ?? false;
    _invertHorizontalScroll =
        config['invert_horizontal_scroll'] as bool? ?? false;
    _themeMode = (config['theme_mode'] as String?) == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
    _preferredTerminalId = config['preferred_terminal'] as String?;
    _bindings = BindingMap.fromJson(config['bindings']);
    _metadataBackend =
        MetadataBackend.fromConfig(config[MetadataBackend.configKey]);

    try {
      _availableTerminals = await _terminalLauncher.detectAvailable();
    } catch (e) {
      debugPrint('Error detecting terminals: $e');
      _availableTerminals = [];
    }

    final lastDir = config['last_visited_directory'] as String?;
    if (lastDir != null && await _repository.directoryExists(lastDir)) {
      _currentDirectory = lastDir;
    } else {
      if (_currentDirectory == p.dirname(Platform.resolvedExecutable)) {
        final home = Platform.isWindows
            ? Platform.environment['USERPROFILE']
            : Platform.environment['HOME'];
        if (home != null && await _repository.directoryExists(home)) {
          _currentDirectory = home;
        }
      }
    }

    await loadDirectory(_currentDirectory, addToHistory: false);
    _initialized = true;
    await _saveGlobalConfig();
    notifyListeners();
  }

  Future<void> _saveGlobalConfig() async {
    if (!_initialized) return;
    try {
      await _repository.updateConfig((config) {
        config['invert_vertical_scroll'] = _invertVerticalScroll;
        config['invert_horizontal_scroll'] = _invertHorizontalScroll;
        config['theme_mode'] = _themeMode == ThemeMode.light ? 'light' : 'dark';
        if (_preferredTerminalId != null) {
          config['preferred_terminal'] = _preferredTerminalId;
        } else {
          config.remove('preferred_terminal');
        }
        config['bindings'] = _bindings.toJson();
        config[MetadataBackend.configKey] = _metadataBackend.configValue;
        return config;
      });
    } catch (e) {
      debugPrint('Error saving settings: $e');
      _setError("Couldn't save settings");
    }
  }

  void _startPolling() {
    _stopPolling();
    _refreshTimer = Timer.periodic(Duration(seconds: 2), (_) {
      _pollForChanges();
    });
  }

  void _stopPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _pollForChanges() async {
    if (_isInteracting || _pollInFlight) return;
    _pollInFlight = true;
    try {
      final entities = await _repository.listEntities(_currentDirectory);
      if (_isInteracting)
        return; // an interaction may have started while awaiting above
      final currentNames = entities.map((e) => e.name).toSet();

      if (currentNames != _lastPolledEntityNames) {
        _lastPolledEntityNames = currentNames;
        await loadDirectory(_currentDirectory,
            addToHistory: false, force: true, isPolledRefresh: true);
      }
    } catch (e) {
      debugPrint('Error polling for directory changes: $e');
    } finally {
      _pollInFlight = false;
    }
  }

  /// Call when the user begins a manual interaction (node drag, canvas pan,
  /// selection box). Suspends polling for the duration so a background
  /// reload can't clobber unsaved, in-memory changes. Pair with
  /// [endInteraction].
  void beginInteraction() {
    _isInteracting = true;
    _stopPolling();
  }

  /// Call when a manual interaction (started with [beginInteraction]) ends,
  /// however it ends - completed, cancelled, or reverted.
  void endInteraction() {
    if (!_isInteracting) return;
    _isInteracting = false;
    if (_initialized && !_isLoading) {
      _startPolling();
    }
  }

  set scale(double value) {
    if (_scale != value) {
      _scale = value;
      notifyListeners();
      _saveViewState();
    }
  }

  set offset(Offset value) {
    if (_offset != value) {
      _offset = value;
      notifyListeners();
      _saveViewState();
    }
  }

  Future<void> _saveViewState() async {
    if (!_initialized) return;
    try {
      await _repository.updateConfig((config) {
        final viewStates =
            Map<String, dynamic>.from(config['desktop_view_states'] ?? {});
        viewStates[_currentDirectory] = {
          'scale': _scale,
          'offset_x': _offset.dx,
          'offset_y': _offset.dy,
        };
        config['desktop_view_states'] = viewStates;
        config['last_visited_directory'] = _currentDirectory;
        return config;
      });
      _viewStateSaveFailed = false;
    } catch (e) {
      debugPrint('Error saving view state: $e');
      if (!_viewStateSaveFailed) {
        _viewStateSaveFailed = true;
        _setError("Couldn't save view state");
      }
    }
  }

  /// Loads [path], serialized against every other disk-touching operation
  /// (polling, create/delete/rename/move) so nothing can race it.
  Future<void> loadDirectory(String path,
      {bool addToHistory = true,
      bool clearForward = true,
      bool force = false,
      bool isPolledRefresh = false}) {
    return _runExclusive(() => _loadDirectoryImpl(
          path,
          addToHistory: addToHistory,
          clearForward: clearForward,
          force: force,
          isPolledRefresh: isPolledRefresh,
        ));
  }

  Future<void> _loadDirectoryImpl(String path,
      {bool addToHistory = true,
      bool clearForward = true,
      bool force = false,
      bool isPolledRefresh = false}) async {
    if (!force && path == _currentDirectory && _nodes.isNotEmpty) return;

    if (_initialized) {
      await _saveViewState();
    }

    final previousPath = _currentDirectory;

    // Deferred: directory search.
    // if (!isPolledRefresh && path != previousPath) {
    //   _cancelNestedSearch();
    // }

    _stopPolling();
    if (!isPolledRefresh) {
      _selectionController.clearSelection();
      _isLoading = true;
      if (_nodes.isEmpty) {
        notifyListeners();
      }
    }

    try {
      if (!await _repository.directoryExists(path)) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (addToHistory && path != _currentDirectory) {
        _history.add(_currentDirectory);
        if (clearForward) {
          _forwardHistory.clear();
        }
      }

      _currentDirectory = path;

      if (_initialized) {
        await _repository.updateConfig((c) {
          c['last_visited_directory'] = _currentDirectory;
          return c;
        });
      }

      Map<String, dynamic> layout = {};
      var layoutLoaded = false;
      if (_layoutIoBlocked(path)) {
        if (path == previousPath) {
          layout = _layoutSnapshotFromNodes();
        }
      } else {
        try {
          // Ensure metadata file exists on first visit, before listing entities,
          // so it appears in the initial render instead of only after renavigating.
          // This never overwrites existing content, so it can't clobber a
          // concurrent save (e.g. from an in-flight drag) with a stale snapshot.
          await _repository.ensureLayoutFileExists(path);
          layout = await _repository.readLayout(path);
          _newElementPlacementConfig =
              await _repository.readNewElementPlacementConfig(path);
          layoutLoaded = true;
          final warning = _repository.takeLayoutWarning(path);
          if (warning != null) {
            _layoutIssuesByPath[path] = warning;
          } else {
            _clearLayoutIssueFor(path);
          }
        } catch (e) {
          debugPrint('Failed to load metadata: $e');
          _setLayoutIssue(path, e);
          if (path == previousPath) {
            layout = _layoutSnapshotFromNodes();
          }
        }
      }

      final entities = await _repository.listEntities(path);

      final usedPositions = <Offset>{};

      final List<DesktopNode> loadedNodes = [];
      final List<DesktopEntity> unpositionedEntities = [];

      for (var e in entities) {
        final name = e.name;

        final nodeLayout = layout[name];
        if (nodeLayout != null) {
          final pos = Offset(nodeLayout['x']?.toDouble() ?? 0.0,
              nodeLayout['y']?.toDouble() ?? 0.0);
          usedPositions.add(pos);

          Color? nodeColor;
          if (nodeLayout['color'] != null) {
            nodeColor = Color(nodeLayout['color'] as int);
          }

          loadedNodes.add(DesktopNode(
            name: name,
            isDirectory: e.isDirectory,
            isSymlink: e.isSymlink,
            position: pos,
            color: nodeColor,
          ));
        } else {
          unpositionedEntities.add(e);
        }
      }

      for (var e in unpositionedEntities) {
        final name = e.name;

        final pos = _findNextPositionUsingConfig(
          _newElementPlacementConfig,
          usedPositions,
          gridSize,
        );
        usedPositions.add(pos);
        loadedNodes.add(DesktopNode(
          name: name,
          isDirectory: e.isDirectory,
          isSymlink: e.isSymlink,
          position: pos,
        ));
      }

      _nodes = List.unmodifiable(loadedNodes);

      if (layoutLoaded && unpositionedEntities.isNotEmpty) {
        await _saveMetadata();
      }

      // Only restore view state from disk if navigating to a different directory.
      // During polled refreshes of the same directory, preserve current pan/zoom.
      if (!isPolledRefresh || path != _currentDirectory) {
        final config = await _repository.readConfig();
        final viewStates =
            (config['desktop_view_states'] as Map?)?.cast<String, dynamic>();
        if (viewStates != null && viewStates.containsKey(path)) {
          final state = viewStates[path];
          _scale = state['scale']?.toDouble() ?? 1.0;
          _offset = Offset(
            state['offset_x']?.toDouble() ?? 0.0,
            state['offset_y']?.toDouble() ?? 0.0,
          );
        } else {
          _scale = 1.0;
          _offset = Offset.zero;
        }
      }
    } catch (e) {
      debugPrint('Error loading directory: $e');
      _setError("Couldn't load this folder");
    } finally {
      _isLoading = false;
      _lastPolledEntityNames = _nodes.map((n) => n.name).toSet();
      _startPolling();
      notifyListeners();
      // Deferred: directory search.
      // if (!isPolledRefresh &&
      //     _searchIncludeNested &&
      //     _searchQuery.trim().isNotEmpty) {
      //   unawaited(_runNestedSearch());
      // }
    }
  }

  /// Replace the node named [name] with the result of [update], if present.
  /// Returns whether a node was found and replaced.
  bool _replaceNode(String name, DesktopNode Function(DesktopNode) update) {
    final index = _nodes.indexWhere((n) => n.name == name);
    if (index == -1) return false;
    final updated = List<DesktopNode>.of(_nodes);
    updated[index] = update(updated[index]);
    _nodes = List.unmodifiable(updated);
    return true;
  }

  /// Find a node by name, or null if not found.
  DesktopNode? _findNode(String name) {
    try {
      return _nodes.firstWhere((n) => n.name == name);
    } catch (e) {
      return null;
    }
  }

  void updateNodePosition(String name, Offset delta) {
    if (_replaceNode(name, (n) => n.copyWith(position: n.position + delta))) {
      notifyListeners();
    }
  }

  Future<void> snapNodeToGrid(String name) {
    return _runExclusive(() async {
      if (_replaceNode(
          name,
          (n) =>
              n.copyWith(position: coords.snapToNearestGridCell(n.position)))) {
        notifyListeners();
        await _saveMetadata();
      }
    });
  }

  Future<void> updateNodeColor(String name, Color? color) {
    return _runExclusive(() async {
      if (_replaceNode(name, (n) => n.copyWith(color: color))) {
        notifyListeners();
        await _saveMetadata();
      }
    });
  }

  Future<void> createFile(String name,
      {Offset? gridPosition, Offset? originalLogicalPos}) {
    return _runExclusive(() async {
      final created =
          await _repository.createFile(p.join(_currentDirectory, name));
      if (created) {
        await _loadDirectoryImpl(_currentDirectory,
            addToHistory: false, force: true);
        if (gridPosition != null) {
          if (_replaceNode(name, (n) => n.copyWith(position: gridPosition))) {
            await _saveMetadata();
          }
        }
      }
    });
  }

  Future<void> createDirectory(String name,
      {Offset? gridPosition, Offset? originalLogicalPos}) {
    return _runExclusive(() async {
      final created =
          await _repository.createDirectory(p.join(_currentDirectory, name));
      if (created) {
        await _loadDirectoryImpl(_currentDirectory,
            addToHistory: false, force: true);
        if (gridPosition != null) {
          if (_replaceNode(name, (n) => n.copyWith(position: gridPosition))) {
            await _saveMetadata();
          }
        }
      }
    });
  }

  Future<void> deleteNode(String name) {
    return _runExclusive(() async {
      final path = p.join(_currentDirectory, name);
      try {
        await _repository.delete(path);
        debugPrint('Deleted: $path');
      } catch (e) {
        debugPrint('Error deleting: $e');
        _setError("Couldn't delete $name");
        return;
      }

      try {
        if (!_layoutIoBlocked(_currentDirectory)) {
          await _repository.removeFromLayout(_currentDirectory, name);
        }
        debugPrint('Removed $name from metadata');
      } catch (e) {
        debugPrint('Failed to update metadata during delete: $e');
        _setLayoutIssue(_currentDirectory, e);
      }

      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    });
  }

  Future<void> renameNode(String oldName, String newName) {
    return _runExclusive(() async {
      final oldPath = p.join(_currentDirectory, oldName);
      final newPath = p.join(_currentDirectory, newName);

      try {
        await _repository.rename(oldPath, newPath);
      } catch (e) {
        debugPrint('Error renaming: $e');
        _setError("Couldn't rename $oldName");
        return;
      }

      try {
        if (!_layoutIoBlocked(_currentDirectory)) {
          await _repository.renameInLayout(_currentDirectory, oldName, newName);
        }
      } catch (e) {
        debugPrint('Failed to update metadata during rename: $e');
        _setLayoutIssue(_currentDirectory, e);
      }

      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    });
  }

  Future<void> refresh() async {
    _layoutIssuesByPath.remove(_currentDirectory);
    await loadDirectory(_currentDirectory, addToHistory: false, force: true);
  }

  Future<String> runScript(String tool, String fileName) async {
    final path = p.join(_currentDirectory, fileName);
    try {
      final result =
          await Process.run(tool, [path], workingDirectory: _currentDirectory);
      final output = result.stdout.toString() + result.stderr.toString();
      return output.isNotEmpty ? output : "Success (no output)";
    } catch (e) {
      return "Error: $e";
    }
  }

  /// Working directory for Open in Terminal given a node in the current listing.
  String terminalDirectoryForNode(DesktopNode node) {
    return node.isDirectory
        ? p.join(_currentDirectory, node.name)
        : _currentDirectory;
  }

  TerminalApp? _resolveTerminal(String? terminalId) {
    if (_availableTerminals.isEmpty) return null;
    if (terminalId != null) {
      for (final app in _availableTerminals) {
        if (app.id == terminalId) return app;
      }
    }
    if (_preferredTerminalId != null) {
      for (final app in _availableTerminals) {
        if (app.id == _preferredTerminalId) return app;
      }
    }
    return _availableTerminals.first;
  }

  Future<void> openInTerminal({
    String? workingDirectory,
    String? terminalId,
  }) async {
    final cwd = workingDirectory ?? _currentDirectory;
    final app = _resolveTerminal(terminalId);
    if (app == null) {
      _setError("Couldn't find a terminal emulator");
      return;
    }
    if (terminalId != null &&
        app.id == terminalId &&
        terminalId != _preferredTerminalId) {
      _preferredTerminalId = terminalId;
      notifyListeners();
      await _saveGlobalConfig();
    }
    try {
      await _terminalLauncher.openShell(app: app, workingDirectory: cwd);
    } catch (e) {
      debugPrint("Failed to launch terminal: $e");
      _setError("Couldn't open a terminal at $cwd");
    }
  }

  Future<void> runInTerminal(String tool, String fileName) async {
    final path = p.join(_currentDirectory, fileName);
    final app = _resolveTerminal(null);
    if (app == null) {
      _setError("Couldn't find a terminal emulator");
      return;
    }
    try {
      await _terminalLauncher.runTool(
        app: app,
        workingDirectory: _currentDirectory,
        tool: tool,
        filePath: path,
      );
    } catch (e) {
      debugPrint("Failed to launch terminal: $e");
      _setError("Couldn't run $fileName in a terminal");
    }
  }

  /// Save the current positions of selected nodes before dragging starts.
  /// Call this from onPanDown to capture pre-drag state.
  void startDrag(Set<String> nodeNames) {
    beginInteraction();
    _dragStartPositions.clear();
    for (final nodeName in nodeNames) {
      final node = _findNode(nodeName);
      if (node != null) {
        _dragStartPositions[nodeName] = node.position;
      }
    }
  }

  /// Clear drag state without moving anything. Call this when a pan gesture
  /// is claimed by a competing recognizer (e.g. it resolves to a plain tap
  /// instead of a drag), so stale start-positions don't linger.
  void cancelDrag() {
    endInteraction();
    if (_dragStartPositions.isEmpty) return;
    _dragStartPositions.clear();
    notifyListeners();
  }

  /// Revert dragged nodes to their pre-drag positions. Call this when a move fails.
  void revertDragPositions(Set<String> nodeNames) {
    for (final nodeName in nodeNames) {
      if (_dragStartPositions.containsKey(nodeName)) {
        _replaceNode(nodeName,
            (n) => n.copyWith(position: _dragStartPositions[nodeName]!));
      }
    }
    notifyListeners();
    _dragStartPositions.clear();
    endInteraction();
  }

  /// Attempt to move nodes to a directory or snap to grid with collision detection.
  /// First checks if cursor is over a directory widget or breadcrumb to trigger a move.
  /// If no drop target is found, snaps to grid and reverts on collision.
  Future<void> completeOrRevertDrag(
    Set<String> nodeNames, {
    Offset? cursorPosition,
  }) {
    if (nodeNames.isEmpty) {
      endInteraction();
      return Future.value();
    }
    return _runExclusive(() async {
      try {
        // Calculate what the snapped positions would be
        final snappedPositions = <String, Offset>{};
        for (final nodeName in nodeNames) {
          final node = _findNode(nodeName);
          if (node != null) {
            snappedPositions[nodeName] =
                coords.snapToNearestGridCell(node.position);
          }
        }

        // Get occupied positions (all nodes except those being moved)
        final occupied = getOccupiedPositions(_nodes, excludeNames: nodeNames);

        // Check if snapped positions would cause collisions
        final snappedOffsets = snappedPositions.values.toList();
        final canPlace = canPlaceNodes(snappedOffsets, occupied);

        if (canPlace) {
          // No collision - apply snaps
          for (final entry in snappedPositions.entries) {
            _replaceNode(entry.key, (n) => n.copyWith(position: entry.value));
          }
        } else {
          // Collision detected - revert to pre-drag positions
          for (final nodeName in nodeNames) {
            if (_dragStartPositions.containsKey(nodeName)) {
              _replaceNode(nodeName,
                  (n) => n.copyWith(position: _dragStartPositions[nodeName]!));
            }
          }
        }

        notifyListeners();
        _dragStartPositions.clear();
        await _saveMetadata();
      } finally {
        endInteraction();
      }
    });
  }

  /// Resolves conflicts when moving nodes by skipping conflicting items.
  /// Call this after a [MoveConflictException] and the user chooses to skip conflicts.
  Future<void> moveNodesToDirectorySkippingConflicts(
      Set<String> nodeNames, String targetPath) {
    return _runExclusive(() async {
      try {
        final filteredNodeNames =
            nodeNames.where((n) => n != MetadataManager.fileName).toSet();
        if (filteredNodeNames.isEmpty || targetPath == _currentDirectory)
          return;

        try {
          final targetLayout = await _repository.readLayout(targetPath);
          // Filter to only non-conflicting names
          final nonConflicting = filteredNodeNames
              .where((name) => !targetLayout.containsKey(name))
              .toSet();

          if (nonConflicting.isEmpty) {
            debugPrint('All items have conflicts, skipping move');
            return;
          }

          // Move only the non-conflicting items
          await _performMove(nonConflicting, targetPath);
        } catch (e) {
          debugPrint('Error moving non-conflicting items: $e');
          _setError("Couldn't move some items to that directory");
        }
      } finally {
        endInteraction();
      }
    });
  }

  /// Move a set of nodes to a target directory and auto-place them.
  /// Uses the same column-wrapping auto-placement logic.
  /// Does not navigate to the target directory.
  /// Throws [MoveConflictException] if naming conflicts are detected.
  Future<void> moveNodesToDirectory(Set<String> nodeNames, String targetPath) {
    return _runExclusive(() async {
      try {
        // Filter out the metadata file (can't move file-tile.json)
        final filteredNodeNames =
            nodeNames.where((n) => n != MetadataManager.fileName).toSet();

        if (filteredNodeNames.isEmpty || targetPath == _currentDirectory)
          return;

        // Check for conflicts before attempting move
        try {
          final targetLayout = await _repository.readLayout(targetPath);
          final conflicts = filteredNodeNames
              .where((name) => targetLayout.containsKey(name))
              .toList();
          if (conflicts.isNotEmpty) {
            throw MoveConflictException(
                conflictingNames: conflicts, targetPath: targetPath);
          }
        } catch (e) {
          if (e is MoveConflictException) rethrow;
          debugPrint('Error checking for conflicts: $e');
        }

        try {
          await _performMove(filteredNodeNames, targetPath);
        } catch (e) {
          debugPrint('Error moving nodes to directory: $e');
          _setError("Couldn't move items to that directory");
        }
      } finally {
        endInteraction();
      }
    });
  }

  Future<void> _performMove(Set<String> nodeNames, String targetPath) async {
    try {
      // Move each node in the filesystem
      for (final nodeName in nodeNames) {
        final sourcePath = p.join(_currentDirectory, nodeName);
        final destPath = p.join(targetPath, nodeName);
        await _repository.rename(sourcePath, destPath);
      }

      // Read source layout to preserve attributes during move
      final sourceLayout = await _repository.readLayout(_currentDirectory);

      // Preserve node attributes before removing from source layout
      final movedNodeData = <String, Map<String, dynamic>>{};
      for (final nodeName in nodeNames) {
        if (sourceLayout.containsKey(nodeName)) {
          movedNodeData[nodeName] =
              Map<String, dynamic>.from(sourceLayout[nodeName] as Map);
        }
      }

      // Update layout for source directory (remove moved nodes)
      try {
        for (final nodeName in nodeNames) {
          sourceLayout.remove(nodeName);
        }
        await _repository.updateLayout(_currentDirectory, sourceLayout);
      } catch (e) {
        debugPrint('Failed to update source directory layout: $e');
      }

      // Auto-place moved nodes in target directory
      try {
        final targetLayout = await _repository.readLayout(targetPath);
        final targetPlacementConfig =
            await _repository.readNewElementPlacementConfig(targetPath);
        final usedPositions = <Offset>{};
        for (final entry in targetLayout.entries) {
          final pos = Offset(
            entry.value['x']?.toDouble() ?? 0.0,
            entry.value['y']?.toDouble() ?? 0.0,
          );
          usedPositions.add(pos);
        }

        // Find positions for moved nodes using target directory's config
        for (final nodeName in nodeNames) {
          final pos = _findNextPositionUsingConfig(
            targetPlacementConfig,
            usedPositions,
            gridSize,
          );
          usedPositions.add(pos);

          // Preserve all attributes from source except position
          final newEntry =
              Map<String, dynamic>.from(movedNodeData[nodeName] ?? {});
          newEntry['x'] = pos.dx;
          newEntry['y'] = pos.dy;
          targetLayout[nodeName] = newEntry;
        }

        // Save target directory layout
        await _repository.updateLayout(targetPath, targetLayout);
      } catch (e) {
        debugPrint('Failed to auto-place in target directory: $e');
      }

      // Reload source directory (stays in current view)
      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveMetadata() async {
    if (_layoutIoBlocked(_currentDirectory)) return;
    final layout = {for (var node in _nodes) node.name: node.toJson()};
    try {
      await _repository.updateLayout(_currentDirectory, layout);
      final warning = _repository.takeLayoutWarning(_currentDirectory);
      if (warning != null) {
        _layoutIssuesByPath[_currentDirectory] = warning;
      } else {
        _clearLayoutIssueFor(_currentDirectory);
      }
    } catch (e) {
      debugPrint('Failed to save metadata: $e');
      _setLayoutIssue(_currentDirectory, e);
    }
  }

  Map<String, dynamic> _layoutSnapshotFromNodes() {
    return {
      for (final node in _nodes) node.name: node.toJson(),
    };
  }

  void navigateUp() {
    final parent = p.dirname(_currentDirectory);
    if (parent != _currentDirectory) {
      loadDirectory(parent);
    }
  }

  void selectNode(String nodeName, {bool multiSelect = false}) {
    if (multiSelect) {
      _selectionController.toggleSelect(nodeName);
    } else {
      _selectionController.selectSingle(nodeName);
    }
    notifyListeners();
  }

  void deselectNode() {
    _selectionController.clearSelection();
    notifyListeners();
  }

  /// Performs a select action on all selected nodes.
  Future<void> performSelectAction(DesktopSelectAction action) async {
    if (_selectionController.selected.isEmpty) return;

    switch (action) {
      case DesktopSelectAction.delete:
        await _performDelete();
      case DesktopSelectAction.openInTerminal:
        await openSelectedInTerminal();
      case DesktopSelectAction.copy:
        await copySelection();
      case DesktopSelectAction.cut:
        await cutSelection();
    }
  }

  Future<void> copySelection() async {
    _captureClipboard(isCut: false);
    await _writeOsClipboard();
  }

  Future<void> cutSelection() async {
    _captureClipboard(isCut: true);
    await _writeOsClipboard();
  }

  void _captureClipboard({required bool isCut}) {
    final names = _selectionController.selected
        .where((n) => n != MetadataManager.fileName)
        .toList();
    if (names.isEmpty) return;
    _clipboard = DesktopClipboard(
      sourceDirectory: _currentDirectory,
      names: names,
      isCut: isCut,
    );
    notifyListeners();
  }

  Future<void> _writeOsClipboard() async {
    final clip = _clipboard;
    if (clip == null || clip.names.isEmpty) return;
    try {
      await _osClipboard.write(
        [for (final name in clip.names) p.join(clip.sourceDirectory, name)],
        isCut: clip.isCut,
      );
    } catch (e) {
      debugPrint('OS clipboard write failed: $e');
    }
  }

  Future<void> _clearOsClipboard() async {
    try {
      await _osClipboard.clear();
    } catch (e) {
      debugPrint('OS clipboard clear failed: $e');
    }
  }

  Future<OsFileClipboardSnapshot?> _resolvePasteSource() async {
    try {
      final os = await _osClipboard.read();
      if (os != null && os.paths.isNotEmpty) return os;
    } catch (e) {
      debugPrint('OS clipboard read failed: $e');
    }
    final clip = _clipboard;
    if (clip == null || clip.names.isEmpty) return null;
    return OsFileClipboardSnapshot(
      paths: [
        for (final name in clip.names) p.join(clip.sourceDirectory, name)
      ],
      isCut: clip.isCut,
    );
  }

  Future<bool> paste({Offset? at, bool skipConflicts = false}) {
    return _runExclusive(() async {
      final source = await _resolvePasteSource();
      if (source == null || source.paths.isEmpty) return false;
      return _importPathsImpl(
        source.paths,
        isCut: source.isCut,
        at: at,
        destDir: _currentDirectory,
        skipConflicts: skipConflicts,
        clearClipboardOnCut: true,
        errorVerb: 'paste',
      );
    });
  }

  /// Copy or move [paths] into [destDir] (defaults to the open folder).
  /// Same conflict and placement rules as paste. Used by OS drop.
  Future<bool> importPaths(
    List<String> paths, {
    required bool isCut,
    Offset? at,
    String? destDir,
    bool skipConflicts = false,
  }) {
    return _runExclusive(() => _importPathsImpl(
          paths,
          isCut: isCut,
          at: at,
          destDir: destDir ?? _currentDirectory,
          skipConflicts: skipConflicts,
          clearClipboardOnCut: false,
          errorVerb: 'drop',
        ));
  }

  Future<bool> _importPathsImpl(
    List<String> paths, {
    required bool isCut,
    Offset? at,
    required String destDir,
    required bool skipConflicts,
    required bool clearClipboardOnCut,
    required String errorVerb,
  }) async {
    final items = [
      for (final path in paths)
        if (p.basename(path) != MetadataManager.fileName)
          (
            path: path,
            name: p.basename(path),
            sourceDir: p.dirname(path),
          ),
    ];
    if (items.isEmpty) return false;

    final allFromHere = items.every((item) => item.sourceDir == destDir);

    if (isCut && allFromHere) {
      if (destDir == _currentDirectory) {
        await _placePastedNodes([for (final item in items) item.name], at);
        if (clearClipboardOnCut) {
          _clipboard = null;
          await _clearOsClipboard();
        }
        notifyListeners();
        return true;
      }
      return true;
    }

    List<DesktopEntity> destEntities;
    try {
      destEntities = await _repository.listEntities(destDir);
    } catch (e) {
      _setError("Couldn't $errorVerb here");
      return false;
    }
    final taken = destEntities.map((e) => e.name).toSet();

    final destNames = <String>[];
    final conflicts = <String>[];
    var working = List.of(items);

    if (allFromHere) {
      for (final item in working) {
        destNames.add(uniqueCopyName(item.name, taken));
        taken.add(destNames.last);
      }
    } else {
      for (final item in working) {
        if (taken.contains(item.name)) {
          conflicts.add(item.name);
        } else {
          destNames.add(item.name);
        }
      }
      if (conflicts.isNotEmpty && !skipConflicts) {
        throw MoveConflictException(
          conflictingNames: conflicts,
          targetPath: destDir,
          attemptedNames: [for (final item in items) item.name],
        );
      }
      if (skipConflicts) {
        working =
            working.where((item) => !conflicts.contains(item.name)).toList();
        destNames
          ..clear()
          ..addAll([for (final item in working) item.name]);
      }
    }

    if (working.isEmpty) return false;

    final importedNames = <String>[];
    final moved = <({String path, String name, String sourceDir})>[];
    try {
      if (isCut) {
        for (var i = 0; i < working.length; i++) {
          final item = working[i];
          final destPath = p.join(destDir, destNames[i]);
          if (await _isInvalidMove(item.path, destPath)) {
            continue;
          }
          await _repository.rename(item.path, destPath);
          importedNames.add(destNames[i]);
          moved.add(item);
        }
        final sourceDirs = {for (final item in moved) item.sourceDir};
        for (final sourceDir in sourceDirs) {
          try {
            if (!_layoutIoBlocked(sourceDir)) {
              final sourceLayout = await _repository.readLayout(sourceDir);
              for (final item in moved.where((i) => i.sourceDir == sourceDir)) {
                sourceLayout.remove(item.name);
              }
              await _repository.updateLayout(sourceDir, sourceLayout);
            }
          } catch (e) {
            debugPrint('Failed to update source layout after cut: $e');
          }
        }
        if (clearClipboardOnCut && moved.isNotEmpty) {
          _clipboard = null;
          await _clearOsClipboard();
        }
      } else {
        for (var i = 0; i < working.length; i++) {
          final item = working[i];
          final destPath = p.join(destDir, destNames[i]);
          if (await _isInvalidMove(item.path, destPath)) {
            continue;
          }
          await _repository.copyEntry(item.path, destPath);
          importedNames.add(destNames[i]);
        }
      }
    } catch (e) {
      debugPrint('Import failed: $e');
      _setError("Couldn't $errorVerb");
      return false;
    }

    if (importedNames.isEmpty) return false;

    if (destDir == _currentDirectory) {
      await _loadDirectoryImpl(destDir, addToHistory: false, force: true);
      await _placePastedNodes(importedNames, at);
    } else {
      await _autoPlaceNamesInLayout(destDir, importedNames);
      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    }
    return true;
  }

  Future<void> _autoPlaceNamesInLayout(
      String targetPath, List<String> names) async {
    if (names.isEmpty) return;
    if (_layoutIoBlocked(targetPath)) return;
    try {
      final targetLayout = await _repository.readLayout(targetPath);
      final targetPlacementConfig =
          await _repository.readNewElementPlacementConfig(targetPath);
      final usedPositions = <Offset>{};
      for (final entry in targetLayout.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        usedPositions.add(Offset(
          (value['x'] as num?)?.toDouble() ?? 0.0,
          (value['y'] as num?)?.toDouble() ?? 0.0,
        ));
      }
      for (final name in names) {
        final pos = _findNextPositionUsingConfig(
          targetPlacementConfig,
          usedPositions,
          gridSize,
        );
        usedPositions.add(pos);
        final existing = targetLayout[name];
        final newEntry = existing is Map
            ? Map<String, dynamic>.from(existing)
            : <String, dynamic>{};
        newEntry['x'] = pos.dx;
        newEntry['y'] = pos.dy;
        targetLayout[name] = newEntry;
      }
      await _repository.updateLayout(targetPath, targetLayout);
    } catch (e) {
      debugPrint('Failed to auto-place in target directory: $e');
    }
  }

  Future<bool> _isInvalidMove(String sourcePath, String destPath) async {
    try {
      final entities = await _repository.listEntities(p.dirname(sourcePath));
      final name = p.basename(sourcePath);
      final isDir = entities.any((e) => e.name == name && e.isDirectory);
      if (!isDir) return false;
      return destPath == sourcePath || p.isWithin(sourcePath, destPath);
    } catch (_) {
      return destPath == sourcePath || p.isWithin(sourcePath, destPath);
    }
  }

  Future<void> _placePastedNodes(List<String> names, Offset? at) async {
    if (names.isEmpty) return;
    final occupied = getOccupiedPositions(_nodes, excludeNames: names.toSet());
    Offset? nextSlot = at;
    for (final name in names) {
      final Offset pos;
      if (nextSlot == null || occupied.contains(nextSlot)) {
        pos = _findNextPositionUsingConfig(
          _newElementPlacementConfig,
          occupied,
          gridSize,
        );
      } else {
        pos = nextSlot;
      }
      _replaceNode(name, (n) => n.copyWith(position: pos));
      occupied.add(pos);
      nextSlot = _findNextPositionUsingConfig(
        _newElementPlacementConfig,
        occupied,
        gridSize,
      );
    }
    notifyListeners();
    await _saveMetadata();
  }

  /// After another app accepts an outbound move, remove leftovers and reload.
  Future<void> finalizeExternalMove(List<String> paths) {
    return _runExclusive(() async {
      for (final path in paths) {
        try {
          await _repository.delete(path);
        } catch (_) {}
      }
      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    });
  }

  // Deferred: directory search (filter + nested walk).
  // static const _maxNestedHits = 250;
  //
  // void setSearchQuery(String query) {
  //   if (_searchQuery == query) return;
  //   _searchQuery = query;
  //   _nestedHits = [];
  //   notifyListeners();
  //   _panToFirstVisibleMatch();
  //   unawaited(_runNestedSearch());
  // }
  //
  // void setSearchIncludeNested(bool value) {
  //   if (_searchIncludeNested == value) return;
  //   _searchIncludeNested = value;
  //   _nestedHits = [];
  //   notifyListeners();
  //   unawaited(_runNestedSearch());
  // }
  //
  // void _cancelNestedSearch() {
  //   _searchEpoch++;
  //   _nestedHits = [];
  //   _nestedSearchInProgress = false;
  // }
  //
  // void _panToFirstVisibleMatch() {
  //   final matches = visibleNodes;
  //   if (matches.isEmpty) return;
  //   final node = matches.first;
  //   _offset = const Offset(80, 80) - node.position * _scale;
  //   notifyListeners();
  // }
  //
  // Future<void> openSearchHit(NestedSearchHit hit) async {
  //   final parent = p.dirname(hit.path);
  //   await loadDirectory(parent);
  //   selectNode(hit.name);
  //   final node = _findNode(hit.name);
  //   if (node != null) {
  //     _offset = const Offset(80, 80) - node.position * _scale;
  //     notifyListeners();
  //   }
  // }
  //
  // Future<void> _runNestedSearch() async {
  //   final epoch = ++_searchEpoch;
  //   final query = _searchQuery.trim().toLowerCase();
  //   if (!_searchIncludeNested || query.isEmpty) {
  //     _nestedHits = [];
  //     _nestedSearchInProgress = false;
  //     notifyListeners();
  //     return;
  //   }
  //
  //   _nestedSearchInProgress = true;
  //   _nestedHits = [];
  //   notifyListeners();
  //
  //   final root = _currentDirectory;
  //   final hits = <NestedSearchHit>[];
  //
  //   Future<void> walk(String dir, String rel) async {
  //     if (epoch != _searchEpoch) return;
  //     while (_isInteracting) {
  //       await Future.delayed(const Duration(milliseconds: 50));
  //       if (epoch != _searchEpoch) return;
  //     }
  //     List<DesktopEntity> entities;
  //     try {
  //       entities = await _repository.listEntities(dir);
  //     } catch (_) {
  //       return;
  //     }
  //     for (final entity in entities) {
  //       if (epoch != _searchEpoch) return;
  //       if (hits.length >= _maxNestedHits) return;
  //       if (entity.name == MetadataManager.fileName) continue;
  //       final childRel = rel.isEmpty ? entity.name : '$rel/${entity.name}';
  //       final isCurrentDir = rel.isEmpty;
  //       if (!isCurrentDir && entity.name.toLowerCase().contains(query)) {
  //         hits.add(NestedSearchHit(
  //           path: p.join(dir, entity.name),
  //           relativePath: childRel,
  //           isDirectory: entity.isDirectory,
  //         ));
  //         if (hits.length % 16 == 0) {
  //           _nestedHits = List.of(hits);
  //           notifyListeners();
  //         }
  //       }
  //       if (entity.isDirectory && !entity.isSymlink) {
  //         await walk(p.join(dir, entity.name), childRel);
  //       }
  //     }
  //   }
  //
  //   await walk(root, '');
  //   if (epoch != _searchEpoch) return;
  //   _nestedHits = hits;
  //   _nestedSearchInProgress = false;
  //   notifyListeners();
  // }

  Future<void> openSelectedInTerminal({String? terminalId}) async {
    final selected = _selectionController.selected;
    if (selected.isEmpty) return;
    final node = _findNode(selected.first);
    if (node == null || !node.isDirectory) return;
    await openInTerminal(
      workingDirectory: terminalDirectoryForNode(node),
      terminalId: terminalId,
    );
  }

  Future<void> _performDelete() async {
    final nodesToDelete = _selectionController.selected.toList();
    for (final nodeName in nodesToDelete) {
      await deleteNode(nodeName);
    }
  }

  void back() {
    if (canGoBack) {
      final previous = _history.removeLast();
      _forwardHistory.add(_currentDirectory);
      loadDirectory(previous, addToHistory: false);
    }
  }

  void forward() {
    if (canGoForward) {
      final next = _forwardHistory.removeLast();
      _history.add(_currentDirectory);
      loadDirectory(next, addToHistory: false);
    }
  }

  @override
  void dispose() {
    _stopPolling();
    // Deferred: directory search.
    // _searchEpoch++;
    _selectionController.removeListener(_onSelectionChanged);
    thumbnailCache.removeListener(_onThumbnailsChanged);
    thumbnailCache.dispose();
    super.dispose();
  }

  int _getGridIndexSkippingZero(int anchor, int offset, bool goingPositive) {
    final result = anchor + (goingPositive ? offset : -offset);
    if (goingPositive && anchor < 0 && result >= 0) {
      return result + 1;
    } else if (!goingPositive && anchor > 0 && result <= 0) {
      return result - 1;
    }
    return result == 0 ? (goingPositive ? 1 : -1) : result;
  }

  Offset _findNextPositionUsingConfig(
    NewElementPlacementConfig config,
    Set<Offset> usedPositions,
    double gridSize,
  ) {
    final isConstrainedHorizontal = config.isConstrainedAxisColumns;

    // Search for the next available position starting from anchor
    int constrainedIndex = 0;
    int unconstrainedIndex = 0;

    while (true) {
      // Calculate grid position based on constrained/unconstrained directions
      int gridCol;
      int gridRow;

      if (isConstrainedHorizontal) {
        // Constrained direction is horizontal (left/right)
        gridCol = _getGridIndexSkippingZero(
          config.anchorCol,
          constrainedIndex,
          config.constrainedDirection == 'right',
        );
        gridRow = _getGridIndexSkippingZero(
          config.anchorRow,
          unconstrainedIndex,
          config.unconstrainedDirection == 'down',
        );
      } else {
        // Constrained direction is vertical (up/down)
        gridRow = _getGridIndexSkippingZero(
          config.anchorRow,
          constrainedIndex,
          config.constrainedDirection == 'down',
        );
        gridCol = _getGridIndexSkippingZero(
          config.anchorCol,
          unconstrainedIndex,
          config.unconstrainedDirection == 'right',
        );
      }

      // Convert grid indices to logical pixels (1-based for positive)
      final logicalX =
          gridCol > 0 ? (gridCol - 1) * gridSize : gridCol * gridSize;
      final logicalY =
          gridRow > 0 ? (gridRow - 1) * gridSize : gridRow * gridSize;
      final pos = Offset(logicalX, logicalY);

      // Check if this position is available
      if (!usedPositions.contains(pos)) {
        return pos;
      }

      // Move to next position: increment constrained first, then unconstrained
      constrainedIndex++;
      if (constrainedIndex >= config.constrainedCount) {
        constrainedIndex = 0;
        unconstrainedIndex++;
      }
    }
  }
}
