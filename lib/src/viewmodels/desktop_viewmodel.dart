import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/path_service.dart';
import '../services/project_root_config_service.dart';

class DesktopNode {
  final String name;
  final bool isDirectory;
  Offset position;
  Color? color;

  DesktopNode({
    required this.name,
    required this.isDirectory,
    this.position = Offset.zero,
    this.color,
  });

  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    if (color != null) 'color': color!.value,
  };
}

class DesktopViewModel extends ChangeNotifier {
  late String _currentDirectory;
  List<DesktopNode> _nodes = [];
  bool _isLoading = false;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _initialized = false;

  String? _selectedNodeName;

  Color _directoryColor = const Color(0xFFEBC351);
  Color _fileColor = const Color(0xFF64B5F6);

  bool _invertVerticalScroll = false;
  bool _invertHorizontalScroll = false;

  bool get invertVerticalScroll => _invertVerticalScroll;
  bool get invertHorizontalScroll => _invertHorizontalScroll;

  final List<String> _history = [];
  final List<String> _forwardHistory = [];

  static const double gridSize = 80.0;

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
  double get scale => _scale;
  Offset get offset => _offset;
  Color get directoryColor => _directoryColor;
  Color get fileColor => _fileColor;
  String? get selectedNodeName => _selectedNodeName;

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

  DesktopViewModel() {
    _currentDirectory = PathService.baseDir;
    _init();
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
    }
  }

  Future<void> openSystemDefault(String fileName) async {
    final path = p.join(_currentDirectory, fileName);
    try {
      await Process.run('xdg-open', [path], workingDirectory: _currentDirectory);
    } catch (e) {
      debugPrint("Failed to open with xdg-open: $e");
    }
  }

  Future<void> _init() async {
    await _checkAppAvailability();
    final config = await ProjectRootConfigService.readLocalConfig();

    if (config['directory_color'] != null) {
      _directoryColor = Color(config['directory_color'] as int);
    }
    if (config['file_color'] != null) {
      _fileColor = Color(config['file_color'] as int);
    }

    _invertVerticalScroll = config['invert_vertical_scroll'] as bool? ?? false;
    _invertHorizontalScroll = config['invert_horizontal_scroll'] as bool? ?? false;

    final lastDir = config['last_visited_directory'] as String?;
    if (lastDir != null && await Directory(lastDir).exists()) {
      _currentDirectory = lastDir;
    } else {
      if (_currentDirectory == p.dirname(Platform.resolvedExecutable)) {
        final home = Platform.isWindows ? Platform.environment['USERPROFILE'] : Platform.environment['HOME'];
        if (home != null && await Directory(home).exists()) {
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
    await ProjectRootConfigService.updateLocalConfig((config) {
      config['directory_color'] = _directoryColor.value;
      config['file_color'] = _fileColor.value;
      config['invert_vertical_scroll'] = _invertVerticalScroll;
      config['invert_horizontal_scroll'] = _invertHorizontalScroll;
      return config;
    });
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
    await ProjectRootConfigService.updateLocalConfig((config) {
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
  }

  Future<void> loadDirectory(String path, {bool addToHistory = true, bool clearForward = true, bool force = false}) async {
    if (!force && path == _currentDirectory && _nodes.isNotEmpty) return;

    if (_initialized) {
      await _saveViewState();
    }

    _selectedNodeName = null;
    _isLoading = true;
    notifyListeners();

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
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

      final String oldDirectory = _currentDirectory;
      _currentDirectory = path;

      final config = await ProjectRootConfigService.readLocalConfig();
      final viewStates = config['desktop_view_states'] as Map<String, dynamic>?;
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
        config['last_visited_directory'] = _currentDirectory;
        await ProjectRootConfigService.writeLocalConfig(config);
      }

      final entities = await dir.list().toList();

      final metadataFile = File(p.join(path, 'stitch-grid.json'));
      Map<String, dynamic> layout = {};
      if (await metadataFile.exists()) {
        try {
          final content = await metadataFile.readAsString();
          final data = json.decode(content);
          layout = data['layout'] ?? {};
        } catch (e) {
          debugPrint('Failed to load metadata: $e');
        }
      }

      final usedPositions = <Offset>{};
      double nextX = 0;
      double nextY = 0;

      final List<DesktopNode> loadedNodes = [];
      final List<FileSystemEntity> unpositionedEntities = [];

      for (var e in entities) {
        final name = p.basename(e.path);
        if (name == 'stitch-grid.json') continue;

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
            isDirectory: e is Directory,
            position: pos,
            color: nodeColor,
          ));
        } else {
          unpositionedEntities.add(e);
        }
      }

      for (var e in unpositionedEntities) {
        final name = p.basename(e.path);

        while (usedPositions.contains(Offset(nextX, nextY))) {
          nextX += gridSize;
          if (nextX >= gridSize * 5) {
            nextX = 0;
            nextY += gridSize;
          }
        }

        final pos = Offset(nextX, nextY);
        usedPositions.add(pos);
        loadedNodes.add(DesktopNode(
          name: name,
          isDirectory: e is Directory,
          position: pos,
        ));
      }

      _nodes = loadedNodes;

      if (unpositionedEntities.isNotEmpty) {
        _saveMetadata();
      }

    } catch (e) {
      debugPrint('Error loading directory: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateNodePosition(String name, Offset delta) {
    final index = _nodes.indexWhere((n) => n.name == name);
    if (index != -1) {
      _nodes[index].position += delta;
      notifyListeners();
    }
  }

  void snapNodeToGrid(String name) {
    final index = _nodes.indexWhere((n) => n.name == name);
    if (index != -1) {
      final pos = _nodes[index].position;
      final snappedX = (pos.dx / gridSize).round() * gridSize;
      final snappedY = (pos.dy / gridSize).round() * gridSize;
      _nodes[index].position = Offset(snappedX, snappedY);
      notifyListeners();
      _saveMetadata();
    }
  }

  Future<void> updateNodeColor(String name, Color? color) async {
    final index = _nodes.indexWhere((n) => n.name == name);
    if (index != -1) {
      _nodes[index].color = color;
      notifyListeners();
      await _saveMetadata();
    }
  }

  Future<void> createFile(String name, {Offset? gridPosition}) async {
    final file = File(p.join(_currentDirectory, name));
    if (!await file.exists()) {
      await file.create();
      await loadDirectory(_currentDirectory, addToHistory: false, force: true);
      if (gridPosition != null) {
        final index = _nodes.indexWhere((n) => n.name == name);
        if (index != -1) {
          _nodes[index].position = gridPosition;
          await _saveMetadata();
        }
      }
    }
  }

  Future<void> createDirectory(String name, {Offset? gridPosition}) async {
    final dir = Directory(p.join(_currentDirectory, name));
    if (!await dir.exists()) {
      await dir.create();
      await loadDirectory(_currentDirectory, addToHistory: false, force: true);
      if (gridPosition != null) {
        final index = _nodes.indexWhere((n) => n.name == name);
        if (index != -1) {
          _nodes[index].position = gridPosition;
          await _saveMetadata();
        }
      }
    }
  }

  Future<void> deleteNode(String name) async {
    final path = p.join(_currentDirectory, name);
    try {
      if (await File(path).exists()) {
        await File(path).delete();
        debugPrint('Deleted file: $path');
      } else if (await Directory(path).exists()) {
        await Directory(path).delete(recursive: true);
        debugPrint('Deleted directory: $path');
      } else {
        debugPrint('Path does not exist: $path');
      }
    } catch (e) {
      debugPrint('Error deleting: $e');
      rethrow;
    }

    final metadataFile = File(p.join(_currentDirectory, 'stitch-grid.json'));
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final data = json.decode(content);
        final layout = data['layout'] as Map<String, dynamic>?;
        if (layout != null && layout.containsKey(name)) {
          layout.remove(name);
          await metadataFile.writeAsString(json.encode(data));
          debugPrint('Removed $name from metadata');
        }
      } catch (e) {
        debugPrint('Failed to update metadata during delete: $e');
      }
    }

    await loadDirectory(_currentDirectory, addToHistory: false, force: true);
  }

  Future<void> renameNode(String oldName, String newName) async {
    final oldPath = p.join(_currentDirectory, oldName);
    final newPath = p.join(_currentDirectory, newName);

    if (await File(oldPath).exists()) {
      await File(oldPath).rename(newPath);
    } else if (await Directory(oldPath).exists()) {
      await Directory(oldPath).rename(newPath);
    }

    final metadataFile = File(p.join(_currentDirectory, 'stitch-grid.json'));
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final data = json.decode(content);
        final layout = data['layout'] as Map<String, dynamic>;
        if (layout.containsKey(oldName)) {
          layout[newName] = layout.remove(oldName);
          await metadataFile.writeAsString(json.encode(data));
        }
      } catch (e) {
        debugPrint('Failed to update metadata during rename: $e');
      }
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

  Future<void> _saveMetadata() async {
    final metadataFile = File(p.join(_currentDirectory, 'stitch-grid.json'));
    final layout = {
      for (var node in _nodes) node.name: node.toJson()
    };
    final data = {
      'version': '1.0',
      'layout': layout,
    };
    await metadataFile.writeAsString(json.encode(data));
  }

  Offset pixelPosToGridPos(Offset pixelPos) {
    final gridX = (pixelPos.dx / gridSize).round() * gridSize;
    final gridY = (pixelPos.dy / gridSize).round() * gridSize;
    return Offset(gridX, gridY);
  }

  void navigateUp() {
    final parent = p.dirname(_currentDirectory);
    if (parent != _currentDirectory) {
      loadDirectory(parent);
    }
  }

  void selectNode(String nodeName) {
    if (_selectedNodeName != nodeName) {
      _selectedNodeName = nodeName;
      notifyListeners();
    }
  }

  void deselectNode() {
    if (_selectedNodeName != null) {
      _selectedNodeName = null;
      notifyListeners();
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
