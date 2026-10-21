import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../controllers/selection_controller.dart';
import '../models/new_element_placement_config.dart';
import '../models/binding_map.dart';
import '../models/edit_history.dart';
import '../models/trash_token.dart';
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
import '../utils/os_file_drop.dart';
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

/// How an in-app drag of tiles already in the open folder would land.
enum InAppCanvasDropKind { intoDirectory, reposition, blocked }

class InAppCanvasDrop {
  final InAppCanvasDropKind kind;
  final String? directoryPath;
  final String? directoryName;
  final Offset? directoryPosition;

  /// Source basename → landing cell. Empty unless [kind] is reposition.
  final Map<String, Offset> placements;
  final String? anchorName;

  const InAppCanvasDrop.intoDirectory({
    required this.directoryPath,
    required this.directoryName,
    required this.directoryPosition,
  })  : kind = InAppCanvasDropKind.intoDirectory,
        placements = const {},
        anchorName = null;

  const InAppCanvasDrop.reposition({
    required this.placements,
    required this.anchorName,
  })  : kind = InAppCanvasDropKind.reposition,
        directoryPath = null,
        directoryName = null,
        directoryPosition = null;

  const InAppCanvasDrop.blocked()
      : kind = InAppCanvasDropKind.blocked,
        directoryPath = null,
        directoryName = null,
        directoryPosition = null,
        placements = const {},
        anchorName = null;
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

enum _HistoryApply { applied, rejected, forgotten }

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
  final EditHistory _edits = EditHistory();

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

  // Every disk-touching operation (load/create/delete/rename/move/undo/poll)
  // runs through this chain so at most one is ever in flight. A newer
  // operation simply awaits the previous one instead of racing it - no
  // request tokens or cancellation needed.
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
  bool get canUndo => _edits.canUndo;
  bool get canRedo => _edits.canRedo;

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

      // First placement into the inbox only. Items that already have a saved
      // position stay put. Oldest modification time takes the anchor cell;
      // newer items continue along the placement region. Equal times break
      // by name so the layout does not depend on directory iteration order.
      unpositionedEntities.sort((a, b) {
        final byTime = (a.modified ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.modified ?? DateTime.fromMillisecondsSinceEpoch(0));
        if (byTime != 0) return byTime;
        return a.name.compareTo(b.name);
      });

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
      final before = _findNode(name)?.toJson();
      if (_replaceNode(
          name,
          (n) =>
              n.copyWith(position: coords.snapToNearestGridCell(n.position)))) {
        notifyListeners();
        await _saveMetadata();
        final after = _findNode(name)?.toJson();
        if (before != null && after != null) {
          _recordLayoutChange(
              _currentDirectory, {name: before}, {name: after});
        }
      }
    });
  }

  Future<void> updateNodeColor(String name, Color? color) {
    return _runExclusive(() async {
      final before = _findNode(name)?.toJson();
      if (before == null) return;
      if (_replaceNode(name, (n) => n.copyWith(color: color))) {
        notifyListeners();
        await _saveMetadata();
        final after = _findNode(name)?.toJson();
        if (after != null) {
          _recordLayoutChange(
              _currentDirectory, {name: before}, {name: after});
        }
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
        _rememberNewNode(name);
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
        _rememberNewNode(name);
      }
    });
  }

  Future<void> createSymlink(String name, String target,
      {Offset? gridPosition, Offset? originalLogicalPos}) {
    return _runExclusive(() async {
      final linkPath = p.join(_currentDirectory, name);
      try {
        final created = await _repository.createSymlink(linkPath, target);
        if (!created) {
          _setError("Couldn't create symlink $name");
          return;
        }
      } catch (e) {
        debugPrint('Error creating symlink: $e');
        _setError("Couldn't create symlink $name");
        return;
      }

      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
      if (gridPosition != null) {
        if (_replaceNode(name, (n) => n.copyWith(position: gridPosition))) {
          await _saveMetadata();
        }
      }
      _rememberNewNode(name);
    });
  }

  Future<void> deleteNode(String name) {
    return _runExclusive(() async {
      final item = await _deleteOne(name);
      if (!item.removed) return;
      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
      if (item.item != null) _record(DeletedEdit([item.item!]));
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
      _record(RenameEdit(
        directory: _currentDirectory,
        oldName: oldName,
        newName: newName,
      ));
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
        final before = <String, Map<String, dynamic>>{};
        for (final name in nodeNames) {
          final start = _dragStartPositions[name];
          final node = _findNode(name);
          if (start == null || node == null) continue;
          before[name] = {
            'x': start.dx,
            'y': start.dy,
            if (node.color != null) 'color': node.color!.toARGB32(),
          };
        }

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
        if (canPlace) {
          _recordLayoutChange(
            _currentDirectory,
            before,
            _clonedNodeLayouts(before.keys),
          );
        }
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
    final sourceDir = _currentDirectory;
    final sourceLayouts = <String, Map<String, dynamic>?>{};
    try {
      if (!_layoutIoBlocked(sourceDir)) {
        final sourceLayout = await _repository.readLayout(sourceDir);
        for (final name in nodeNames) {
          sourceLayouts[name] = _layoutValue(sourceLayout[name]);
        }
      }
    } catch (e) {
      debugPrint('Failed to read source layout before move: $e');
    }

    final renamed = <String>[];
    final destLayouts = <String, Map<String, dynamic>>{};
    try {
      for (final nodeName in nodeNames) {
        final sourcePath = p.join(sourceDir, nodeName);
        final destPath = p.join(targetPath, nodeName);
        await _repository.rename(sourcePath, destPath);
        renamed.add(nodeName);
      }

      try {
        if (!_layoutIoBlocked(sourceDir)) {
          final sourceLayout = await _repository.readLayout(sourceDir);
          for (final nodeName in renamed) {
            sourceLayout.remove(nodeName);
          }
          await _repository.updateLayout(sourceDir, sourceLayout);
        }
      } catch (e) {
        debugPrint('Failed to update source directory layout: $e');
      }

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

        for (final nodeName in renamed) {
          final pos = _findNextPositionUsingConfig(
            targetPlacementConfig,
            usedPositions,
            gridSize,
          );
          usedPositions.add(pos);

          final newEntry =
              Map<String, dynamic>.from(sourceLayouts[nodeName] ?? {});
          newEntry['x'] = pos.dx;
          newEntry['y'] = pos.dy;
          targetLayout[nodeName] = newEntry;
          destLayouts[nodeName] = Map<String, dynamic>.from(newEntry);
        }

        await _repository.updateLayout(targetPath, targetLayout);
      } catch (e) {
        debugPrint('Failed to auto-place in target directory: $e');
      }

      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    } finally {
      if (renamed.isNotEmpty) {
        _record(MoveEdit(
          destDir: targetPath,
          items: [
            for (final name in renamed)
              MoveEditItem(
                sourceDir: sourceDir,
                name: name,
                sourceLayout: sourceLayouts[name],
                destLayout: destLayouts[name],
              ),
          ],
        ));
      }
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

  /// Where an in-app drag of tiles in the open folder would land.
  ///
  /// Returns null when [paths] are not all tiles in this folder (an external
  /// drop). The directory under the pointer receives every dragged tile.
  /// Any other occupied cell in the footprint — including a directory the
  /// pointer is not on — blocks the whole drop.
  ///
  /// [anchorPath] is the tile the OS drag image represents. [dropCell] is the
  /// cell that image would land on. [vacateSources] is true for a move: those
  /// cells are free. A copy keeps them occupied.
  InAppCanvasDrop? resolveInAppCanvasDrop({
    required List<String> paths,
    required String? anchorPath,
    required Offset dropCell,
    required bool vacateSources,
    DesktopNode? cursorNode,
  }) {
    if (anchorPath == null || paths.isEmpty) return null;
    if (p.dirname(anchorPath) != _currentDirectory) return null;
    final anchorName = p.basename(anchorPath);
    if (_findNode(anchorName) == null) return null;

    final names = <String>[];
    for (final path in paths) {
      if (p.dirname(path) != _currentDirectory) return null;
      final name = p.basename(path);
      if (name == MetadataManager.fileName) continue;
      if (_findNode(name) == null) return null;
      names.add(name);
    }
    if (names.isEmpty || !names.contains(anchorName)) return null;

    if (cursorNode != null &&
        cursorNode.isDirectory &&
        !names.contains(cursorNode.name)) {
      final dest = p.join(_currentDirectory, cursorNode.name);
      if (isDropIntoSelf(dest, paths)) return const InAppCanvasDrop.blocked();
      return InAppCanvasDrop.intoDirectory(
        directoryPath: dest,
        directoryName: cursorNode.name,
        directoryPosition: cursorNode.position,
      );
    }

    final anchor = _findNode(anchorName)!;
    final delta = dropCell - anchor.position;
    final placements = <String, Offset>{
      for (final name in names) name: _findNode(name)!.position + delta,
    };
    if (!_exactPlacementsFit(placements, vacateSources: vacateSources)) {
      return const InAppCanvasDrop.blocked();
    }
    return InAppCanvasDrop.reposition(
      placements: placements,
      anchorName: anchorName,
    );
  }

  /// True when every landing cell is free.
  /// A move vacates the tiles being placed; a copy does not.
  bool _exactPlacementsFit(
    Map<String, Offset> placements, {
    required bool vacateSources,
  }) {
    if (placements.isEmpty) return false;
    final occupied = getOccupiedPositions(
      _nodes,
      excludeNames: vacateSources ? placements.keys.toSet() : const <String>{},
    );
    return canPlaceNodes(placements.values.toList(), occupied);
  }

  /// Moves every named tile to its cell, or none of them.
  bool _applyExactPlacements(Map<String, Offset> placements) {
    if (!_exactPlacementsFit(placements, vacateSources: true)) return false;
    for (final name in placements.keys) {
      if (_findNode(name) == null) return false;
    }
    for (final entry in placements.entries) {
      _replaceNode(entry.key, (n) => n.copyWith(position: entry.value));
    }
    notifyListeners();
    return true;
  }

  /// Copy or move [paths] into [destDir] (defaults to the open folder).
  /// Same conflict and placement rules as paste. Used by OS drop.
  ///
  /// [placements] maps source basenames to landing cells for a same-folder
  /// drop. Every tile lands there, or none do.
  Future<bool> importPaths(
    List<String> paths, {
    required bool isCut,
    Offset? at,
    String? destDir,
    bool skipConflicts = false,
    Map<String, Offset>? placements,
  }) {
    return _runExclusive(() => _importPathsImpl(
          paths,
          isCut: isCut,
          at: at,
          destDir: destDir ?? _currentDirectory,
          skipConflicts: skipConflicts,
          clearClipboardOnCut: false,
          errorVerb: 'drop',
          placements: placements,
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
    Map<String, Offset>? placements,
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
        final names = [for (final item in items) item.name];
        final before = _clonedNodeLayouts(names);
        if (placements != null && placements.isNotEmpty) {
          final wanted = <String, Offset>{};
          for (final item in items) {
            final pos = placements[item.name];
            if (pos == null) return false;
            wanted[item.name] = pos;
          }
          if (!_applyExactPlacements(wanted)) return false;
          await _saveMetadata();
        } else {
          await _placePastedNodes(names, at);
        }
        _recordLayoutChange(
          _currentDirectory,
          before,
          _clonedNodeLayouts(names),
        );
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

    Map<String, Offset>? copyPlacements;
    if (!isCut &&
        placements != null &&
        placements.isNotEmpty &&
        allFromHere &&
        destDir == _currentDirectory) {
      final wanted = <String, Offset>{};
      for (final item in working) {
        final pos = placements[item.name];
        if (pos == null) return false;
        wanted[item.name] = pos;
      }
      if (!_exactPlacementsFit(wanted, vacateSources: false)) return false;
      copyPlacements = {
        for (var i = 0; i < working.length; i++)
          destNames[i]: wanted[working[i].name]!,
      };
    }

    final importedNames = <String>[];
    final moved = <({String path, String name, String sourceDir})>[];
    final sourceLayouts = <String, Map<String, Map<String, dynamic>?>>{};
    if (isCut) {
      for (final dir in {for (final item in working) item.sourceDir}) {
        try {
          if (_layoutIoBlocked(dir)) continue;
          final layout = await _repository.readLayout(dir);
          sourceLayouts[dir] = {
            for (final item in working.where((i) => i.sourceDir == dir))
              item.name: _layoutValue(layout[item.name]),
          };
        } catch (e) {
          debugPrint('Failed to read source layout before move: $e');
        }
      }
    }
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
      if (isCut && moved.isNotEmpty) {
        _rememberMove(
          destDir: destDir,
          moved: moved,
          sourceLayouts: sourceLayouts,
          destLayout: const {},
        );
      } else if (!isCut && importedNames.isNotEmpty) {
        _rememberCreated(destDir, importedNames, const {});
      }
      return false;
    }

    if (importedNames.isEmpty) return false;

    if (destDir == _currentDirectory) {
      await _loadDirectoryImpl(destDir, addToHistory: false, force: true);
      if (copyPlacements != null) {
        if (_applyExactPlacements(copyPlacements)) {
          await _saveMetadata();
        }
      } else {
        await _placePastedNodes(importedNames, at);
      }
    } else {
      await _autoPlaceNamesInLayout(destDir, importedNames);
      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    }
    final destLayout = await _readLayoutOrEmpty(destDir);
    if (isCut) {
      _rememberMove(
        destDir: destDir,
        moved: moved,
        sourceLayouts: sourceLayouts,
        destLayout: destLayout,
      );
    } else {
      _rememberCreated(destDir, importedNames, destLayout);
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

  /// Finish an outbound drag.
  ///
  /// A move trashes whatever is still at [paths], and undo puts it back.
  /// When the other app has already removed a path, [restoreTaken] puts the
  /// drag-start snapshot back so that move can be undone too. A copy or
  /// cancel leaves a surviving file where it is; if one was taken anyway,
  /// [restoreTaken] puts it back immediately.
  /// [releaseUnused] drops snapshots that were not put back.
  Future<void> finalizeExternalMove(
    List<String> paths, {
    bool deleteIfPresent = true,
    Future<bool> Function(String originalPath)? restoreTaken,
    Future<void> Function()? releaseUnused,
  }) {
    return _runExclusive(() async {
      try {
        final items = <DeletedEditItem>[];
        var changed = false;
        for (final path in paths) {
          final directory = p.dirname(path);
          final name = p.basename(path);
          if (name.isEmpty || name == MetadataManager.fileName) continue;
          final layout = await _layoutFor(directory, name);
          final present = await _containsName(directory, name);
          if (present == true && !deleteIfPresent) continue;
          if (present == false) {
            final restored = await _restoreTaken(restoreTaken, path);
            if (!restored) continue;
            changed = true;
            if (!deleteIfPresent) continue;
          } else if (present == null && !deleteIfPresent) {
            continue;
          }

          final TrashToken? token;
          try {
            token = await _repository.delete(path);
          } catch (_) {
            continue;
          }
          changed = true;
          try {
            if (!_layoutIoBlocked(directory)) {
              await _repository.removeFromLayout(directory, name);
            }
          } catch (e) {
            debugPrint('Failed to update metadata during external move: $e');
            _setLayoutIssue(directory, e);
          }
          if (token == null) continue;
          items.add(DeletedEditItem(
            directory: directory,
            name: name,
            layout: layout,
            token: token,
          ));
        }
        if (changed) {
          await _loadDirectoryImpl(_currentDirectory,
              addToHistory: false, force: true);
        }
        if (items.isNotEmpty) _record(DeletedEdit(items));
      } finally {
        await releaseUnused?.call();
      }
    });
  }

  Future<bool> _restoreTaken(
    Future<bool> Function(String originalPath)? restoreTaken,
    String path,
  ) async {
    if (restoreTaken == null) return false;
    try {
      return await restoreTaken(path);
    } catch (e) {
      debugPrint('Drag snapshot restore failed for $path: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> _layoutFor(String directory, String name) async {
    if (directory == _currentDirectory) {
      final existing = _findNode(name)?.toJson();
      if (existing == null) return null;
      return Map<String, dynamic>.from(existing);
    }
    return _layoutValue((await _readLayoutOrEmpty(directory))[name]);
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

  Future<void> _performDelete() {
    final nodesToDelete = _selectionController.selected.toList();
    if (nodesToDelete.isEmpty) return Future.value();
    return _runExclusive(() async {
      final items = <DeletedEditItem>[];
      var removedAny = false;
      for (final nodeName in nodesToDelete) {
        final result = await _deleteOne(nodeName);
        if (result.removed) removedAny = true;
        final item = result.item;
        if (item != null) items.add(item);
      }
      if (removedAny) {
        await _loadDirectoryImpl(_currentDirectory,
            addToHistory: false, force: true);
      }
      if (items.isNotEmpty) _record(DeletedEdit(items));
    });
  }

  Future<void> undo() => _runExclusive(_undoImpl);

  Future<void> redo() => _runExclusive(_redoImpl);

  Future<void> _undoImpl() async {
    final entry = _edits.takeUndo();
    if (entry == null) return;
    final result = await _revert(entry);
    switch (result) {
      case _HistoryApply.applied:
        _edits.noteRedo(entry);
      case _HistoryApply.rejected:
        _edits.noteUndo(entry);
      case _HistoryApply.forgotten:
        break;
    }
    notifyListeners();
  }

  Future<void> _redoImpl() async {
    final entry = _edits.takeRedo();
    if (entry == null) return;
    final result = await _reapply(entry);
    switch (result) {
      case _HistoryApply.applied:
        _edits.noteUndo(entry);
      case _HistoryApply.rejected:
        _edits.noteRedo(entry);
      case _HistoryApply.forgotten:
        break;
    }
    notifyListeners();
  }

  Future<({DeletedEditItem? item, bool removed})> _deleteOne(String name) async {
    final path = p.join(_currentDirectory, name);
    final existing = _findNode(name)?.toJson();
    final TrashToken? token;
    try {
      token = await _repository.delete(path);
      debugPrint('Deleted: $path');
    } catch (e) {
      debugPrint('Error deleting: $e');
      _setError("Couldn't delete $name");
      return (item: null, removed: false);
    }

    try {
      if (!_layoutIoBlocked(_currentDirectory)) {
        await _repository.removeFromLayout(_currentDirectory, name);
      }
    } catch (e) {
      debugPrint('Failed to update metadata during delete: $e');
      _setLayoutIssue(_currentDirectory, e);
    }

    final item = token == null
        ? null
        : DeletedEditItem(
            directory: _currentDirectory,
            name: name,
            layout:
                existing == null ? null : Map<String, dynamic>.from(existing),
            token: token,
          );
    return (item: item, removed: true);
  }

  void _record(EditEntry entry) {
    _edits.push(entry);
    notifyListeners();
  }

  void _rememberNewNode(String name) {
    final node = _findNode(name);
    _record(CreatedEdit(
      directory: _currentDirectory,
      items: [
        CreatedEditItem(
          name: name,
          layout: node == null ? null : Map<String, dynamic>.from(node.toJson()),
        ),
      ],
      tokens: [null],
    ));
  }

  void _rememberCreated(
    String directory,
    List<String> names,
    Map<String, dynamic> destLayout,
  ) {
    if (names.isEmpty) return;
    _record(CreatedEdit(
      directory: directory,
      items: [
        for (final name in names)
          CreatedEditItem(name: name, layout: _layoutValue(destLayout[name])),
      ],
      tokens: List<TrashToken?>.filled(names.length, null),
    ));
  }

  void _rememberMove({
    required String destDir,
    required List<({String path, String name, String sourceDir})> moved,
    required Map<String, Map<String, Map<String, dynamic>?>> sourceLayouts,
    required Map<String, dynamic> destLayout,
  }) {
    if (moved.isEmpty) return;
    _record(MoveEdit(
      destDir: destDir,
      items: [
        for (final item in moved)
          MoveEditItem(
            sourceDir: item.sourceDir,
            name: item.name,
            sourceLayout: sourceLayouts[item.sourceDir]?[item.name],
            destLayout: _layoutValue(destLayout[item.name]),
          ),
      ],
    ));
  }

  Map<String, dynamic>? _layoutValue(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  Map<String, Map<String, dynamic>> _clonedNodeLayouts(Iterable<String> names) {
    final layouts = <String, Map<String, dynamic>>{};
    for (final name in names) {
      final node = _findNode(name);
      if (node != null) layouts[name] = node.toJson();
    }
    return layouts;
  }

  void _recordLayoutChange(
    String directory,
    Map<String, Map<String, dynamic>> before,
    Map<String, Map<String, dynamic>> after,
  ) {
    final beforeChanged = <String, Map<String, dynamic>>{};
    final afterChanged = <String, Map<String, dynamic>>{};
    for (final name in before.keys) {
      final next = after[name];
      if (next == null || _sameLayout(before[name]!, next)) continue;
      beforeChanged[name] = Map<String, dynamic>.from(before[name]!);
      afterChanged[name] = Map<String, dynamic>.from(next);
    }
    if (beforeChanged.isEmpty) return;
    _record(LayoutEdit(
      directory: directory,
      before: beforeChanged,
      after: afterChanged,
    ));
  }

  bool _sameLayout(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _readLayoutOrEmpty(String directory) async {
    if (directory == _currentDirectory) {
      return {for (final node in _nodes) node.name: node.toJson()};
    }
    try {
      if (_layoutIoBlocked(directory)) return {};
      return await _repository.readLayout(directory);
    } catch (e) {
      debugPrint('Failed to read layout for undo: $e');
      return {};
    }
  }

  Future<_HistoryApply> _revert(EditEntry entry) {
    return switch (entry) {
      MoveEdit move => _applyMove(move, forward: false),
      CreatedEdit created => _undoCreated(created),
      DeletedEdit deleted => _undoDeleted(deleted),
      RenameEdit renamed => _applyRename(renamed, undo: true),
      LayoutEdit layout => _applyLayout(layout, undo: true),
    };
  }

  Future<_HistoryApply> _reapply(EditEntry entry) {
    return switch (entry) {
      MoveEdit move => _applyMove(move, forward: true),
      CreatedEdit created => _redoCreated(created),
      DeletedEdit deleted => _redoDeleted(deleted),
      RenameEdit renamed => _applyRename(renamed, undo: false),
      LayoutEdit layout => _applyLayout(layout, undo: false),
    };
  }

  String _historyError({required bool undo, required bool missing}) {
    final verb = undo ? 'undo' : 'redo';
    if (missing) return "Can't $verb — those items aren't there anymore";
    return "Can't $verb — a file with that name is already there";
  }

  Future<bool?> _containsName(String directory, String name) async {
    try {
      final entities = await _repository.listEntities(directory);
      return entities.any((e) => e.name == name);
    } catch (e) {
      debugPrint('Failed to list $directory: $e');
      return null;
    }
  }

  Future<_HistoryApply> _applyMove(MoveEdit edit, {required bool forward}) async {
    for (final item in edit.items) {
      final fromDir = forward ? item.sourceDir : edit.destDir;
      final toDir = forward ? edit.destDir : item.sourceDir;
      final fromExists = await _containsName(fromDir, item.name);
      if (fromExists != true) {
        _setError(_historyError(undo: !forward, missing: true));
        return _HistoryApply.rejected;
      }
      final toExists = await _containsName(toDir, item.name);
      if (toExists == null) {
        _setError(_historyError(undo: !forward, missing: true));
        return _HistoryApply.rejected;
      }
      if (toExists) {
        _setError(_historyError(undo: !forward, missing: false));
        return _HistoryApply.rejected;
      }
    }

    try {
      for (final item in edit.items) {
        final fromDir = forward ? item.sourceDir : edit.destDir;
        final toDir = forward ? edit.destDir : item.sourceDir;
        await _repository.rename(
          p.join(fromDir, item.name),
          p.join(toDir, item.name),
        );
      }
    } catch (e) {
      debugPrint('Move undo failed: $e');
      _setError(forward ? "Can't redo that move" : "Can't undo that move");
      return _HistoryApply.rejected;
    }

    final destUpdates = <String, Map<String, dynamic>?>{
      for (final item in edit.items)
        item.name: forward ? item.destLayout : null,
    };
    await _patchLayouts(edit.destDir, destUpdates);

    final bySource = <String, Map<String, Map<String, dynamic>?>>{};
    for (final item in edit.items) {
      (bySource[item.sourceDir] ??= {})[item.name] =
          forward ? null : item.sourceLayout;
    }
    for (final source in bySource.entries) {
      await _patchLayouts(source.key, source.value);
    }

    if (_currentDirectory == edit.destDir ||
        edit.items.any((item) => item.sourceDir == _currentDirectory)) {
      await _loadDirectoryImpl(_currentDirectory,
          addToHistory: false, force: true);
    }
    return _HistoryApply.applied;
  }

  Future<_HistoryApply> _undoCreated(CreatedEdit edit) async {
    for (var i = 0; i < edit.items.length; i++) {
      if (edit.tokens[i] != null) continue;
      final exists = await _containsName(edit.directory, edit.items[i].name);
      if (exists != true) {
        _setError(_historyError(undo: true, missing: true));
        return _HistoryApply.rejected;
      }
    }

    var restorable = true;
    for (var i = 0; i < edit.items.length; i++) {
      if (edit.tokens[i] != null) continue;
      final name = edit.items[i].name;
      try {
        edit.tokens[i] =
            await _repository.delete(p.join(edit.directory, name));
      } catch (e) {
        debugPrint('Undo create failed: $e');
        _setError("Can't undo — couldn't move $name to the trash");
        return _HistoryApply.rejected;
      }
      if (edit.tokens[i] == null) restorable = false;
      try {
        if (!_layoutIoBlocked(edit.directory)) {
          await _repository.removeFromLayout(edit.directory, name);
        }
      } catch (e) {
        debugPrint('Failed to clear layout after undo create: $e');
      }
    }
    await _reloadIfOpen(edit.directory);
    if (!restorable) {
      _setError("Undid that, but it can't be redone");
      return _HistoryApply.forgotten;
    }
    return _HistoryApply.applied;
  }

  Future<_HistoryApply> _redoCreated(CreatedEdit edit) async {
    if (edit.tokens.any((token) => token == null)) {
      _setError("Can't redo that");
      return _HistoryApply.rejected;
    }
    for (final item in edit.items) {
      final exists = await _containsName(edit.directory, item.name);
      if (exists == null) {
        _setError(_historyError(undo: false, missing: true));
        return _HistoryApply.rejected;
      }
      if (exists) {
        _setError(_historyError(undo: false, missing: false));
        return _HistoryApply.rejected;
      }
    }
    try {
      for (var i = 0; i < edit.items.length; i++) {
        await _repository.restore(edit.tokens[i]!);
        edit.tokens[i] = null;
      }
    } catch (e) {
      debugPrint('Redo create failed: $e');
      _setError("Can't redo — the trash entry is gone");
      return _HistoryApply.rejected;
    }
    await _patchLayouts(edit.directory, {
      for (final item in edit.items) item.name: item.layout,
    });
    await _reloadIfOpen(edit.directory);
    return _HistoryApply.applied;
  }

  Future<_HistoryApply> _undoDeleted(DeletedEdit edit) async {
    for (final item in edit.items) {
      final exists = await _containsName(item.directory, item.name);
      if (exists == null) {
        _setError(_historyError(undo: true, missing: true));
        return _HistoryApply.rejected;
      }
      if (exists) {
        _setError(_historyError(undo: true, missing: false));
        return _HistoryApply.rejected;
      }
    }
    try {
      for (final item in edit.items) {
        await _repository.restore(item.token);
      }
    } catch (e) {
      debugPrint('Undo delete failed: $e');
      _setError("Can't undo — the trash entry is gone");
      return _HistoryApply.rejected;
    }
    final byDir = <String, Map<String, Map<String, dynamic>?>>{};
    for (final item in edit.items) {
      (byDir[item.directory] ??= {})[item.name] = item.layout;
    }
    for (final dir in byDir.entries) {
      await _patchLayouts(dir.key, dir.value);
      await _reloadIfOpen(dir.key);
    }
    return _HistoryApply.applied;
  }

  Future<_HistoryApply> _redoDeleted(DeletedEdit edit) async {
    for (final item in edit.items) {
      final exists = await _containsName(item.directory, item.name);
      if (exists != true) {
        _setError(_historyError(undo: false, missing: true));
        return _HistoryApply.rejected;
      }
    }
    final touched = <String>{};
    for (final item in edit.items) {
      final TrashToken? token;
      try {
        token = await _repository.delete(p.join(item.directory, item.name));
      } catch (e) {
        debugPrint('Redo delete failed: $e');
        _setError("Can't redo that delete");
        return _HistoryApply.rejected;
      }
      if (token == null) {
        _setError("Redid that delete, but it can't be undone");
        return _HistoryApply.forgotten;
      }
      item.token = token;
      try {
        if (!_layoutIoBlocked(item.directory)) {
          await _repository.removeFromLayout(item.directory, item.name);
        }
      } catch (e) {
        debugPrint('Failed to clear layout after redo delete: $e');
      }
      touched.add(item.directory);
    }
    for (final dir in touched) {
      await _reloadIfOpen(dir);
    }
    return _HistoryApply.applied;
  }

  Future<_HistoryApply> _applyRename(RenameEdit edit, {required bool undo}) async {
    final from = undo ? edit.newName : edit.oldName;
    final to = undo ? edit.oldName : edit.newName;
    final fromExists = await _containsName(edit.directory, from);
    if (fromExists != true) {
      _setError(_historyError(undo: undo, missing: true));
      return _HistoryApply.rejected;
    }
    final toExists = await _containsName(edit.directory, to);
    if (toExists == null) {
      _setError(_historyError(undo: undo, missing: true));
      return _HistoryApply.rejected;
    }
    if (toExists) {
      _setError(_historyError(undo: undo, missing: false));
      return _HistoryApply.rejected;
    }
    try {
      await _repository.rename(
        p.join(edit.directory, from),
        p.join(edit.directory, to),
      );
      if (!_layoutIoBlocked(edit.directory)) {
        await _repository.renameInLayout(edit.directory, from, to);
      }
    } catch (e) {
      debugPrint('Rename undo failed: $e');
      _setError(undo ? "Can't undo that rename" : "Can't redo that rename");
      return _HistoryApply.rejected;
    }
    await _reloadIfOpen(edit.directory);
    return _HistoryApply.applied;
  }

  Future<_HistoryApply> _applyLayout(LayoutEdit edit, {required bool undo}) async {
    final desired = undo ? edit.before : edit.after;
    for (final name in desired.keys) {
      final exists = await _containsName(edit.directory, name);
      if (exists != true) {
        _setError(_historyError(undo: undo, missing: true));
        return _HistoryApply.rejected;
      }
    }
    await _patchLayouts(edit.directory, {
      for (final entry in desired.entries) entry.key: entry.value,
    });
    await _reloadIfOpen(edit.directory);
    return _HistoryApply.applied;
  }

  Future<void> _patchLayouts(
    String directory,
    Map<String, Map<String, dynamic>?> updates,
  ) async {
    if (updates.isEmpty || _layoutIoBlocked(directory)) return;
    try {
      final layout = await _repository.readLayout(directory);
      for (final entry in updates.entries) {
        if (entry.value == null) {
          layout.remove(entry.key);
        } else {
          layout[entry.key] = Map<String, dynamic>.from(entry.value!);
        }
      }
      await _repository.updateLayout(directory, layout);
    } catch (e) {
      debugPrint('Failed to patch layout: $e');
      _setLayoutIssue(directory, e);
    }
  }

  Future<void> _reloadIfOpen(String directory) async {
    if (directory == _currentDirectory) {
      await _loadDirectoryImpl(directory, addToHistory: false, force: true);
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
