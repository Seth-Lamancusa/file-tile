import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../controllers/selection_controller.dart';
import '../repositories/desktop_repository.dart';
import '../repositories/file_system_desktop_repository.dart';
import '../utils/coordinate_space.dart';
import '../utils/grid_position.dart';

/// Actions that can be performed on selected nodes.
/// This is the single source of truth for select actions in the desktop view.
enum DesktopSelectAction {
  delete,
}

/// Sentinel used by [DesktopNode.copyWith] to distinguish "leave color
/// unchanged" from "set color to null".
const _unset = Object();

class DesktopNode {
  final String name;
  final bool isDirectory;
  final Offset position;
  final Color? color;

  const DesktopNode({
    required this.name,
    required this.isDirectory,
    this.position = Offset.zero,
    this.color,
  });

  DesktopNode copyWith({Offset? position, Object? color = _unset}) {
    return DesktopNode(
      name: name,
      isDirectory: isDirectory,
      position: position ?? this.position,
      color: identical(color, _unset) ? this.color : color as Color?,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    if (color != null) 'color': color!.value,
  };
}

class DesktopViewModel extends ChangeNotifier {
  final DesktopRepository _repository;
  final SelectionController _selectionController = SelectionController();
  late String _currentDirectory;
  List<DesktopNode> _nodes = [];
  bool _isLoading = false;
  String? _lastError;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _initialized = false;

  Color _directoryColor = const Color(0xFFEBC351);
  Color _fileColor = const Color(0xFF64B5F6);

  bool _invertVerticalScroll = false;
  bool _invertHorizontalScroll = false;

  bool get invertVerticalScroll => _invertVerticalScroll;
  bool get invertHorizontalScroll => _invertHorizontalScroll;

  final List<String> _history = [];
  final List<String> _forwardHistory = [];

  // Drag state for collision detection and revert on collision
  final Map<String, Offset> _dragStartPositions = {};

  // Use GridConfig.gridCellSize instead; kept for backwards compatibility
  static const double gridSize = GridConfig.gridCellSize;

  final Map<String, bool> _availableApps = {};
  Map<String, bool> get availableApps => _availableApps;

  final List<Map<String, String>> _appRegistry = [
    {'name': 'VS Code', 'cmd': 'code', 'icon': 'code'},
    {'name': 'Cursor', 'cmd': 'cursor', 'icon': 'terminal'},
    {'name': 'Sublime', 'cmd': 'subl', 'icon': 'edit'},
    {'name': 'Nautilus', 'cmd': 'nautilus', 'icon': 'folder_open'},
  ];
  List<Map<String, String>> get appRegistry => _appRegistry;

  String get currentDirectory => _currentDirectory;
  List<DesktopNode> get nodes => _nodes;
  bool get isLoading => _isLoading;
  bool get isInitialized => _initialized;
  String? get lastError => _lastError;
  double get scale => _scale;
  Offset get offset => _offset;
  Color get directoryColor => _directoryColor;
  Color get fileColor => _fileColor;
  Set<String> get selectedNodeNames => _selectionController.selected;
  bool isNodeSelected(String nodeName) => _selectionController.isSelected(nodeName);
  SelectionController get selectionController => _selectionController;

  /// Coordinate space converter (handles all screen ↔ logical conversions).
  CoordinateSpace get coords => CoordinateSpace(scale: _scale, panOffset: _offset);

  set directoryColor(Color value) {
    if (_directoryColor != value) {
      _directoryColor = value;
      notifyListeners();
      _saveGlobalConfig();
    }
  }

  set fileColor(Color value) {
    if (_fileColor != value) {
      _fileColor = value;
      notifyListeners();
      _saveGlobalConfig();
    }
  }

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

  bool get canGoBack => _history.isNotEmpty;
  bool get canGoForward => _forwardHistory.isNotEmpty;

  DesktopViewModel({DesktopRepository? repository})
      : _repository = repository ?? FileSystemDesktopRepository() {
    _currentDirectory = _repository.initialDirectory;
    _selectionController.addListener(_onSelectionChanged);
    _init();
  }

  void _onSelectionChanged() {
    notifyListeners();
  }

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  /// Call after displaying [lastError] so it isn't shown again.
  void clearError() {
    _lastError = null;
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
      await Process.run('xdg-open', [path], workingDirectory: _currentDirectory);
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

    if (config['directory_color'] != null) {
      _directoryColor = Color(config['directory_color'] as int);
    }
    if (config['file_color'] != null) {
      _fileColor = Color(config['file_color'] as int);
    }

    _invertVerticalScroll = config['invert_vertical_scroll'] as bool? ?? false;
    _invertHorizontalScroll = config['invert_horizontal_scroll'] as bool? ?? false;

    final lastDir = config['last_visited_directory'] as String?;
    if (lastDir != null && await _repository.directoryExists(lastDir)) {
      _currentDirectory = lastDir;
    } else {
      if (_currentDirectory == p.dirname(Platform.resolvedExecutable)) {
        final home = Platform.isWindows ? Platform.environment['USERPROFILE'] : Platform.environment['HOME'];
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
        config['directory_color'] = _directoryColor.value;
        config['file_color'] = _fileColor.value;
        config['invert_vertical_scroll'] = _invertVerticalScroll;
        config['invert_horizontal_scroll'] = _invertHorizontalScroll;
        return config;
      });
    } catch (e) {
      debugPrint('Error saving settings: $e');
      _setError("Couldn't save settings");
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
        final viewStates = Map<String, dynamic>.from(config['desktop_view_states'] ?? {});
        viewStates[_currentDirectory] = {
          'scale': _scale,
          'offset_x': _offset.dx,
          'offset_y': _offset.dy,
        };
        config['desktop_view_states'] = viewStates;
        config['last_visited_directory'] = _currentDirectory;
        return config;
      });
    } catch (e) {
      debugPrint('Error saving view state: $e');
      _setError("Couldn't save view state");
    }
  }

  Future<void> loadDirectory(String path, {bool addToHistory = true, bool clearForward = true, bool force = false}) async {
    if (!force && path == _currentDirectory && _nodes.isNotEmpty) return;

    if (_initialized) {
      await _saveViewState();
    }

    _selectionController.clearSelection();
    _isLoading = true;
    notifyListeners();

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

      final config = await _repository.readConfig();
      final viewStates = (config['desktop_view_states'] as Map?)?.cast<String, dynamic>();
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

      if (_initialized) {
        await _repository.updateConfig((c) {
          c['last_visited_directory'] = _currentDirectory;
          return c;
        });
      }

      Map<String, dynamic> layout = {};
      try {
        layout = await _repository.readLayout(path);
        // Ensure metadata file exists on first visit, before listing entities,
        // so it appears in the initial render instead of only after renavigating.
        await _repository.updateLayout(path, layout);
      } catch (e) {
        debugPrint('Failed to load metadata: $e');
        _setError("Couldn't load saved layout for this folder");
      }

      final entities = await _repository.listEntities(path);

      final usedPositions = <Offset>{};
      double nextX = 0;
      double nextY = 0;

      final List<DesktopNode> loadedNodes = [];
      final List<DesktopEntity> unpositionedEntities = [];

      for (var e in entities) {
        final name = e.name;

        final nodeLayout = layout[name];
        if (nodeLayout != null) {
          final pos = Offset(
            nodeLayout['x']?.toDouble() ?? 0.0,
            nodeLayout['y']?.toDouble() ?? 0.0
          );
          usedPositions.add(pos);

          Color? nodeColor;
          if (nodeLayout['color'] != null) {
            nodeColor = Color(nodeLayout['color'] as int);
          }

          loadedNodes.add(DesktopNode(
            name: name,
            isDirectory: e.isDirectory,
            position: pos,
            color: nodeColor,
          ));
        } else {
          unpositionedEntities.add(e);
        }
      }

      for (var e in unpositionedEntities) {
        final name = e.name;

        final pos = findNextAvailablePosition(
          Offset(nextX, nextY),
          usedPositions,
          gridSize,
          5, // maxColumnsBeforeWrap
        );
        usedPositions.add(pos);
        loadedNodes.add(DesktopNode(
          name: name,
          isDirectory: e.isDirectory,
          position: pos,
        ));

        // Update nextX and nextY for the next search
        nextX = pos.dx + gridSize;
        if ((nextX / gridSize).round() >= 5) {
          nextX = 0;
          nextY = pos.dy + gridSize;
        }
      }

      _nodes = List.unmodifiable(loadedNodes);
      debugPrint('[DesktopViewModel] rendering ${_nodes.length} node(s) for $path: '
          '${_nodes.map((n) => n.name).toList()}');

      if (unpositionedEntities.isNotEmpty) {
        _saveMetadata();
      }

    } catch (e) {
      debugPrint('Error loading directory: $e');
      _setError("Couldn't load this folder");
    } finally {
      _isLoading = false;
      notifyListeners();
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

  void snapNodeToGrid(String name) {
    if (_replaceNode(name, (n) => n.copyWith(position: coords.snapToNearestGridCell(n.position)))) {
      notifyListeners();
      _saveMetadata();
    }
  }

  Future<void> updateNodeColor(String name, Color? color) async {
    if (_replaceNode(name, (n) => n.copyWith(color: color))) {
      notifyListeners();
      await _saveMetadata();
    }
  }

  Future<void> createFile(String name, {Offset? gridPosition, Offset? originalLogicalPos}) async {
    final created = await _repository.createFile(p.join(_currentDirectory, name));
    if (created) {
      await loadDirectory(_currentDirectory, addToHistory: false, force: true);
      if (gridPosition != null) {
        if (_replaceNode(name, (n) => n.copyWith(position: gridPosition))) {
          await _saveMetadata();
        }
      }
    }
  }

  Future<void> createDirectory(String name, {Offset? gridPosition, Offset? originalLogicalPos}) async {
    final created = await _repository.createDirectory(p.join(_currentDirectory, name));
    if (created) {
      await loadDirectory(_currentDirectory, addToHistory: false, force: true);
      if (gridPosition != null) {
        if (_replaceNode(name, (n) => n.copyWith(position: gridPosition))) {
          await _saveMetadata();
        }
      }
    }
  }

  Future<void> deleteNode(String name) async {
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
      final layout = await _repository.readLayout(_currentDirectory);
      layout.remove(name);
      await _repository.updateLayout(_currentDirectory, layout);
      debugPrint('Removed $name from metadata');
    } catch (e) {
      debugPrint('Failed to update metadata during delete: $e');
      _setError("Couldn't update layout after deleting $name");
    }

    await loadDirectory(_currentDirectory, addToHistory: false, force: true);
  }

  Future<void> renameNode(String oldName, String newName) async {
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
      final layout = await _repository.readLayout(_currentDirectory);
      if (layout.containsKey(oldName)) {
        layout[newName] = layout.remove(oldName);
        await _repository.updateLayout(_currentDirectory, layout);
      }
    } catch (e) {
      debugPrint('Failed to update metadata during rename: $e');
      _setError("Couldn't update layout after renaming $oldName");
    }

    await loadDirectory(_currentDirectory, addToHistory: false, force: true);
  }

  Future<void> refresh() async {
    await loadDirectory(_currentDirectory, addToHistory: false, force: true);
  }

  Future<String> runScript(String tool, String fileName) async {
    final path = p.join(_currentDirectory, fileName);
    try {
      final result = await Process.run(tool, [path], workingDirectory: _currentDirectory);
      final output = result.stdout.toString() + result.stderr.toString();
      return output.isNotEmpty ? output : "Success (no output)";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<void> runInTerminal(String tool, String fileName) async {
    final path = p.join(_currentDirectory, fileName);
    final command = '$tool "$path"; echo; read -p "Process finished. Press Enter to close..."';

    try {
      if (Platform.isLinux) {
        try {
          await Process.start('gnome-terminal', ['--', 'bash', '-c', command], workingDirectory: _currentDirectory);
        } catch (_) {
          await Process.start('x-terminal-emulator', ['-e', 'bash', '-c', command], workingDirectory: _currentDirectory);
        }
      }
    } catch (e) {
      debugPrint("Failed to launch terminal: $e");
    }
  }

  /// Save the current positions of selected nodes before dragging starts.
  /// Call this from onPanDown to capture pre-drag state.
  void startDrag(Set<String> nodeNames) {
    _dragStartPositions.clear();
    for (final nodeName in nodeNames) {
      final node = _findNode(nodeName);
      if (node != null) {
        _dragStartPositions[nodeName] = node.position;
      }
    }
  }

  /// Attempt to move nodes to a directory or snap to grid with collision detection.
  /// First checks if cursor is over a directory widget or breadcrumb to trigger a move.
  /// If no drop target is found, snaps to grid and reverts on collision.
  Future<void> completeOrRevertDrag(
    Set<String> nodeNames, {
    Offset? cursorPosition,
  }) async {
    if (nodeNames.isEmpty) return;

    // Check if cursor is over a drop target (directory or breadcrumb)
    // This will be called from the view with cursor position
    // For now, we'll implement the snap-with-collision logic
    // and the move logic will be added after implementing hit-testing

    // Calculate what the snapped positions would be
    final snappedPositions = <String, Offset>{};
    for (final nodeName in nodeNames) {
      final node = _findNode(nodeName);
      if (node != null) {
        snappedPositions[nodeName] = coords.snapToNearestGridCell(node.position);
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
          _replaceNode(nodeName, (n) => n.copyWith(position: _dragStartPositions[nodeName]!));
        }
      }
    }

    notifyListeners();
    _dragStartPositions.clear();
    await _saveMetadata();
  }

  /// Move a set of nodes to a target directory and auto-place them.
  /// Uses the same column-wrapping auto-placement logic.
  /// Does not navigate to the target directory.
  Future<void> moveNodesToDirectory(Set<String> nodeNames, String targetPath) async {
    if (nodeNames.isEmpty || targetPath == _currentDirectory) return;

    try {
      // Move each node in the filesystem
      for (final nodeName in nodeNames) {
        final sourcePath = p.join(_currentDirectory, nodeName);
        final destPath = p.join(targetPath, nodeName);
        await _repository.rename(sourcePath, destPath);
      }

      // Update layout for source directory (remove moved nodes)
      try {
        final layout = await _repository.readLayout(_currentDirectory);
        for (final nodeName in nodeNames) {
          layout.remove(nodeName);
        }
        await _repository.updateLayout(_currentDirectory, layout);
      } catch (e) {
        debugPrint('Failed to update source directory layout: $e');
      }

      // Auto-place moved nodes in target directory
      try {
        final targetLayout = await _repository.readLayout(targetPath);
        final usedPositions = <Offset>{};
        for (final entry in targetLayout.entries) {
          final pos = Offset(
            entry.value['x']?.toDouble() ?? 0.0,
            entry.value['y']?.toDouble() ?? 0.0,
          );
          usedPositions.add(pos);
        }

        // Find positions for moved nodes
        double nextX = 0;
        double nextY = 0;
        for (final nodeName in nodeNames) {
          final pos = findNextAvailablePosition(
            Offset(nextX, nextY),
            usedPositions,
            gridSize,
            5, // maxColumnsBeforeWrap
          );
          usedPositions.add(pos);
          targetLayout[nodeName] = {'x': pos.dx, 'y': pos.dy};

          // Update nextX and nextY for the next search
          nextX = pos.dx + gridSize;
          if ((nextX / gridSize).round() >= 5) {
            nextX = 0;
            nextY = pos.dy + gridSize;
          }
        }

        // Save target directory layout
        await _repository.updateLayout(targetPath, targetLayout);
      } catch (e) {
        debugPrint('Failed to auto-place in target directory: $e');
      }

      // Reload source directory (stays in current view)
      await loadDirectory(_currentDirectory, addToHistory: false, force: true);
    } catch (e) {
      debugPrint('Error moving nodes to directory: $e');
      _setError("Couldn't move items to that directory");
    }
  }

  Future<void> _saveMetadata() async {
    final layout = {
      for (var node in _nodes) node.name: node.toJson()
    };
    await _repository.updateLayout(_currentDirectory, layout);
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
  /// Currently supported: [DesktopSelectAction.delete]
  Future<void> performSelectAction(DesktopSelectAction action) async {
    if (_selectionController.selected.isEmpty) return;

    switch (action) {
      case DesktopSelectAction.delete:
        await _performDelete();
    }
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
}
