import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import '../controllers/click_handler.dart';
import '../services/appimage_updater.dart';
import '../models/binding_map.dart';
import '../models/click_event.dart';
import '../models/directory_layout_issue.dart';
import '../models/metadata_backend.dart';
import '../viewmodels/desktop_viewmodel.dart';
import '../widgets/appimage_update_dialog.dart';
import '../widgets/breadcrumb_segment.dart';
import '../widgets/cascading_menu.dart';
import '../widgets/os_drop_target_overlay.dart';
import '../widgets/placement_region_painter.dart';
import '../widgets/selection_box_painter.dart';
import '../utils/coordinate_space.dart';
import '../utils/drag_out_snapshot.dart';
import '../utils/edge_auto_scroll.dart';
import '../utils/file_icons.dart';
import '../utils/linux_file_picker.dart';
import '../utils/grid_position.dart';
import '../utils/metadata_helper.dart';
import '../utils/os_file_clipboard.dart';
import '../utils/os_file_drop.dart';
import '../theme/file_tile_colors.dart';

export '../viewmodels/desktop_viewmodel.dart'
    show DesktopSelectAction, MoveConflictException;

class DesktopView extends StatefulWidget {
  const DesktopView({super.key});

  @override
  State<DesktopView> createState() => _DesktopViewState();
}

enum _EdgeScrollKind { osDrop, layoutFile }

class _DesktopViewState extends State<DesktopView> {
  late FocusNode _focusNode;
  late ClickHandler _clickHandler;
  String?
      _dragTargetNodeName; // Name of the directory being hovered as a drop target
  String?
      _dragTargetBreadcrumbPath; // Path of the breadcrumb being hovered as a drop target
  final Map<String, GlobalKey> _breadcrumbKeys =
      {}; // Map of path -> GlobalKey for hit-testing
  Offset? _selectionBoxStart;
  Offset? _selectionBoxEnd;
  final GlobalKey _canvasKey = GlobalKey();
  final AppImageUpdater _appImageUpdater = AppImageUpdater();
  List<Offset> _osDropCells = const [];
  Offset? _osDropAnchorCell;
  int _osDropDepth = 0;
  bool _osDragOutDropWasLocal = false;
  List<String> _pendingDropPaths = const [];
  bool _pendingDropCut = true;
  String? _pendingDropDest;
  Offset? _pendingDropAt;
  Map<String, Offset>? _pendingDropPlacements;
  Size? _canvasSize;
  Timer? _edgeScrollTimer;
  _EdgeScrollKind? _edgeScrollKind;
  Offset? _edgeScrollCursor;
  List<String> _edgeScrollPaths = const [];
  String? _edgeScrollAnchor;
  bool _edgeScrollVacate = true;
  String? _layoutDragName;
  Offset? _layoutGrabInCanvas;
  // Deferred: directory search.
  // bool _searchBarOpen = false;
  // late FocusNode _searchFocusNode;
  // late TextEditingController _searchController;
  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    // Deferred: directory search.
    // _searchFocusNode = FocusNode();
    // _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      final viewModel = context.read<DesktopViewModel>();
      _clickHandler = _clickHandler = ClickHandler(
        selectionController: viewModel.selectionController,
        bindings: viewModel.bindings,
      );
      unawaited(_offerAppImageUpdate());
    });
  }

  Future<void> _offerAppImageUpdate() async {
    final status = await _appImageUpdater.checkForUpdate();
    if (!mounted || status != AppImageUpdateStatus.updateAvailable) return;

    final install = await showDialog<bool>(
      context: context,
      builder: (context) => const AppImageUpdatePrompt(),
    );
    if (install != true || !mounted) return;

    final result = await showDialog<AppImageInstallResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        unawaited(() async {
          AppImageInstallResult result;
          try {
            result = await _appImageUpdater.installUpdate();
          } catch (e) {
            result = AppImageInstallResult.failed('$e');
          }
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext, result);
          }
        }());
        return const AppImageUpdateProgress();
      },
    );
    if (!mounted || result == null) return;

    if (!result.installed) {
      await showDialog<void>(
        context: context,
        builder: (context) => AppImageUpdateFailed(message: result.message),
      );
      return;
    }

    final restart = await showDialog<bool>(
      context: context,
      builder: (context) => const AppImageRestartPrompt(),
    );
    if (restart != true || !mounted) return;

    try {
      await _appImageUpdater.relaunch();
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => const AppImageUpdateFailed(
          message: "Couldn't restart. Open File Tile again to use the update.",
        ),
      );
    }
  }

  @override
  void dispose() {
    _stopEdgeAutoScroll();
    _focusNode.dispose();
    // Deferred: directory search.
    // _searchFocusNode.dispose();
    // _searchController.dispose();
    super.dispose();
  }

  List<String> _getNodesInSelectionBox(Offset start, Offset end) {
    final viewModel = context.read<DesktopViewModel>();
    final selectionRect = Rect.fromPoints(start, end);
    final selectedNodeIds = <String>[];

    for (final node in viewModel.nodes) {
      final screenPos = viewModel.coords.logicalToScreen(node.position);
      final nodeRect = Rect.fromLTWH(
        screenPos.dx,
        screenPos.dy,
        GridConfig.gridCellSize * viewModel.scale,
        GridConfig.gridCellSize * viewModel.scale,
      );

      if (selectionRect.overlaps(nodeRect)) {
        selectedNodeIds.add(node.name);
      }
    }

    return selectedNodeIds;
  }

  void _updateVisibleThumbnails(
      DesktopViewModel viewModel, BoxConstraints constraints) {
    final cell = GridConfig.gridCellSize * viewModel.scale;
    // Pad the keep-alive rect so zoom/pan does not drop a thumb for one frame
    // and flash the file icon.
    final pad = cell * 2;
    final keepViewport = Rect.fromLTWH(
      -pad,
      -pad,
      constraints.maxWidth + pad * 2,
      constraints.maxHeight + pad * 2,
    );
    final decodeViewport =
        Rect.fromLTWH(0, 0, constraints.maxWidth, constraints.maxHeight);
    // Below this, GPU-scale whatever is already decoded. Starting new isolates
    // for a directory of postage stamps is what makes zoom-out hitch and flash.
    const minDecodeCell = 28.0;
    final shouldDecode = cell >= minDecodeCell;

    final keep = <String>{};
    final decode = <String>{};
    for (final node in viewModel.nodes) {
      if (node.isDirectory || !isRasterImageFile(node.name)) continue;
      final pos = viewModel.coords.logicalToScreen(node.position);
      final rect = Rect.fromLTWH(pos.dx, pos.dy, cell, cell);
      if (!keepViewport.overlaps(rect)) continue;
      final path = p.join(viewModel.currentDirectory, node.name);
      keep.add(path);
      if (shouldDecode && decodeViewport.overlaps(rect)) {
        decode.add(path);
      }
    }
    viewModel.thumbnailCache.setVisible(keep, decode: decode);
  }

  Offset _globalToCanvas(Offset globalPos) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.globalToLocal(globalPos);
    }
    return globalPos - Offset(0, AppConfig.appBarHeight);
  }

  void _armOsEdgeScroll({
    required Offset global,
    required List<String> localPaths,
    required String? anchorPath,
    required bool vacateSources,
  }) {
    _edgeScrollKind = _EdgeScrollKind.osDrop;
    _edgeScrollCursor = global;
    _edgeScrollPaths = localPaths;
    _edgeScrollAnchor = anchorPath;
    _edgeScrollVacate = vacateSources;
    _ensureEdgeScrollTimer();
  }

  void _armLayoutEdgeScroll(Offset global) {
    _edgeScrollKind = _EdgeScrollKind.layoutFile;
    _edgeScrollCursor = global;
    _ensureEdgeScrollTimer();
  }

  void _ensureEdgeScrollTimer() {
    if (_edgeScrollTimer != null) return;
    _edgeScrollTimer = Timer.periodic(EdgeAutoScroll.tick, (_) {
      _tickEdgeAutoScroll();
    });
  }

  void _tickEdgeAutoScroll() {
    if (!mounted || _edgeScrollKind == null) return;
    final cursor = _edgeScrollCursor;
    final canvasSize = _canvasSize;
    if (cursor == null || canvasSize == null) return;

    final viewModel = context.read<DesktopViewModel>();
    final delta = EdgeAutoScroll.delta(
      canvasLocal: _globalToCanvas(cursor),
      canvasSize: canvasSize,
    );
    if (delta != Offset.zero) {
      viewModel.offset = viewModel.offset + delta;
    }
    if (_edgeScrollKind == _EdgeScrollKind.layoutFile) {
      _pinLayoutFileToCursor(viewModel);
    } else if (delta != Offset.zero) {
      _updateOsDropHover(
        viewModel,
        cursor,
        localPaths: _edgeScrollPaths,
        anchorPath: _edgeScrollAnchor,
        vacateSources: _edgeScrollVacate,
      );
    }
  }

  /// Keep file-tile.json under the pointer while the canvas pans.
  void _pinLayoutFileToCursor(DesktopViewModel viewModel) {
    final name = _layoutDragName;
    final grab = _layoutGrabInCanvas;
    final cursor = _edgeScrollCursor;
    if (name == null || grab == null || cursor == null) return;
    DesktopNode? node;
    for (final candidate in viewModel.nodes) {
      if (candidate.name == name) {
        node = candidate;
        break;
      }
    }
    if (node == null) return;
    final targetScreen = _globalToCanvas(cursor) + grab;
    final delta =
        viewModel.coords.screenToLogical(targetScreen) - node.position;
    if (delta.dx.abs() < 0.01 && delta.dy.abs() < 0.01) return;
    viewModel.updateNodePosition(name, delta);
  }

  void _stopOsEdgeScroll() {
    if (_edgeScrollKind != _EdgeScrollKind.osDrop) return;
    _stopEdgeAutoScroll();
  }

  void _stopLayoutEdgeScroll() {
    if (_edgeScrollKind == _EdgeScrollKind.layoutFile) {
      _stopEdgeAutoScroll();
      return;
    }
    _layoutDragName = null;
    _layoutGrabInCanvas = null;
  }

  void _stopEdgeAutoScroll() {
    _edgeScrollTimer?.cancel();
    _edgeScrollTimer = null;
    _edgeScrollKind = null;
    _edgeScrollCursor = null;
    _layoutDragName = null;
    _layoutGrabInCanvas = null;
  }

  void _osDropEnter(DesktopViewModel viewModel) {
    if (_osDropDepth == 0) viewModel.beginInteraction();
    _osDropDepth++;
  }

  void _osDropLeave(DesktopViewModel viewModel, {required bool breadcrumbs}) {
    if (_osDropDepth == 0) return;
    _osDropDepth--;
    if (_osDropDepth == 0) {
      viewModel.endInteraction();
      if (!breadcrumbs) _stopOsEdgeScroll();
      setState(() {
        _osDropCells = const [];
        _osDropAnchorCell = null;
        _dragTargetNodeName = null;
        _dragTargetBreadcrumbPath = null;
      });
    }
  }

  void _osDropEnded(DesktopViewModel viewModel, {required bool breadcrumbs}) {
    if (_osDropDepth > 0) {
      viewModel.endInteraction();
    }
    _osDropDepth = 0;
    if (!breadcrumbs) _stopOsEdgeScroll();
    if (!mounted) return;
    setState(() {
      _osDropCells = const [];
      _osDropAnchorCell = null;
      _dragTargetNodeName = null;
      _dragTargetBreadcrumbPath = null;
    });
  }

  DropOperation _onOsDropOver(
    DropOverEvent event,
    DesktopViewModel viewModel, {
    required bool breadcrumbs,
  }) {
    if (!dropSessionHasFiles(event.session)) return DropOperation.none;
    final localPaths = fileTileLocalDragPaths(event.session);
    final operation = preferredOsDropOperation(
      controlPressed: HardwareKeyboard.instance.isControlPressed,
      allowed: event.session.allowedOperations,
    );
    if (operation == DropOperation.none) {
      _clearOsDropAim();
      return DropOperation.none;
    }
    if (breadcrumbs) {
      _stopOsEdgeScroll();
      final path = _hitTestBreadcrumb(event.position.global);
      if (path == null || isDropIntoSelf(path, localPaths)) {
        _clearOsDropAim();
        return DropOperation.none;
      }
      setState(() {
        _dragTargetBreadcrumbPath = path;
        _dragTargetNodeName = null;
        _osDropCells = const [];
        _osDropAnchorCell = null;
      });
    } else {
      final vacateSources = fileTileLocalDragIsCut(event.session) ??
          operation == DropOperation.move;
      if (!_updateOsDropHover(
        viewModel,
        event.position.global,
        localPaths: localPaths,
        anchorPath: fileTileLocalDragAnchor(event.session),
        vacateSources: vacateSources,
      )) {
        return DropOperation.none;
      }
      _armOsEdgeScroll(
        global: event.position.global,
        localPaths: localPaths,
        anchorPath: fileTileLocalDragAnchor(event.session),
        vacateSources: vacateSources,
      );
    }
    return operation;
  }

  bool _updateOsDropHover(
    DesktopViewModel viewModel,
    Offset global, {
    required List<String> localPaths,
    required String? anchorPath,
    required bool vacateSources,
  }) {
    final aim = _resolveOsCanvasDropAim(
      viewModel,
      global,
      localPaths,
      anchorPath: anchorPath,
      vacateSources: vacateSources,
    );
    if (aim == null) {
      _clearOsDropAim();
      return false;
    }
    if (aim.folderPath != null) {
      setState(() {
        _dragTargetNodeName = aim.folderName;
        _dragTargetBreadcrumbPath = null;
        _osDropCells = [aim.folderPosition!];
        _osDropAnchorCell = aim.folderPosition;
      });
      return true;
    }
    final cells = aim.placements?.values.toList() ?? [aim.cell!];
    final anchor = aim.anchorName == null
        ? aim.cell!
        : aim.placements![aim.anchorName] ?? aim.cell!;
    setState(() {
      _dragTargetNodeName = null;
      _dragTargetBreadcrumbPath = null;
      _osDropCells = cells;
      _osDropAnchorCell = anchor;
    });
    return true;
  }

  void _clearOsDropAim() {
    if (_osDropCells.isEmpty &&
        _osDropAnchorCell == null &&
        _dragTargetNodeName == null &&
        _dragTargetBreadcrumbPath == null) {
      return;
    }
    setState(() {
      _osDropCells = const [];
      _osDropAnchorCell = null;
      _dragTargetNodeName = null;
      _dragTargetBreadcrumbPath = null;
    });
  }

  DesktopNode? _cursorNode(DesktopViewModel viewModel, Offset global) {
    final hit = _hitTestNode(global, viewModel);
    if (hit != null) return hit;
    final canvas = _globalToCanvas(global);
    final corner = viewModel.coords
        .snapToCellCorner(viewModel.coords.screenToLogical(canvas));
    return _nodeAtCell(viewModel, corner);
  }

  _OsCanvasDropAim? _resolveOsCanvasDropAim(
    DesktopViewModel viewModel,
    Offset global,
    List<String> localPaths, {
    required String? anchorPath,
    required bool vacateSources,
  }) {
    final canvas = _globalToCanvas(global);
    final corner = viewModel.coords
        .snapToCellCorner(viewModel.coords.screenToLogical(canvas));
    final node = _cursorNode(viewModel, global);
    final decision = viewModel.resolveInAppCanvasDrop(
      paths: localPaths,
      anchorPath: anchorPath,
      dropCell: corner,
      vacateSources: vacateSources,
      cursorNode: node,
    );
    if (decision != null) {
      switch (decision.kind) {
        case InAppCanvasDropKind.blocked:
          return null;
        case InAppCanvasDropKind.intoDirectory:
          return _OsCanvasDropAim.folder(
            folderPath: decision.directoryPath!,
            folderName: decision.directoryName!,
            folderPosition: decision.directoryPosition!,
          );
        case InAppCanvasDropKind.reposition:
          return _OsCanvasDropAim.reposition(
            cell: decision.placements[decision.anchorName] ?? corner,
            placements: decision.placements,
            anchorName: decision.anchorName!,
          );
      }
    }
    if (node != null) {
      return _aimForOccupiedNode(viewModel, node, localPaths);
    }
    return _OsCanvasDropAim.cell(corner);
  }

  _OsCanvasDropAim? _aimForOccupiedNode(
    DesktopViewModel viewModel,
    DesktopNode node,
    List<String> localPaths,
  ) {
    final path = p.join(viewModel.currentDirectory, node.name);
    if (localPaths.contains(path)) return null;
    if (!node.isDirectory) return null;
    if (isDropIntoSelf(path, localPaths)) return null;
    return _OsCanvasDropAim.folder(
      folderPath: path,
      folderName: node.name,
      folderPosition: node.position,
    );
  }

  DesktopNode? _hitTestNode(Offset globalPos, DesktopViewModel viewModel) {
    final canvasPos = _globalToCanvas(globalPos);
    final scaledSize = GridConfig.gridCellSize * viewModel.scale;
    for (final node in viewModel.orderedNodes.reversed) {
      final screenPos = viewModel.coords.logicalToScreen(node.position);
      final rect =
          Rect.fromLTWH(screenPos.dx, screenPos.dy, scaledSize, scaledSize);
      if (rect.contains(canvasPos)) return node;
    }
    return null;
  }

  DesktopNode? _nodeAtCell(DesktopViewModel viewModel, Offset corner) {
    for (final node in viewModel.nodes) {
      if (viewModel.coords.snapToCellCorner(node.position) == corner) {
        return node;
      }
    }
    return null;
  }

  Future<void> _onOsPerformDrop(
    PerformDropEvent event,
    DesktopViewModel viewModel, {
    required bool breadcrumbs,
  }) async {
    if (!breadcrumbs) _stopOsEdgeScroll();
    if (isFileTileLocalDrop(event.session)) {
      _osDragOutDropWasLocal = true;
    }
    final defaultCut = event.acceptedOperation != DropOperation.copy;
    final snapshot =
        await readDropSession(event.session, defaultCut: defaultCut);
    if (snapshot == null || snapshot.paths.isEmpty) return;

    final localPaths = fileTileLocalDragPaths(event.session);
    final isCut = fileTileLocalDragIsCut(event.session) ?? snapshot.isCut;
    String? dest;
    Offset? at;
    Map<String, Offset>? placements;
    if (breadcrumbs) {
      dest = _hitTestBreadcrumb(event.position.global);
      if (dest == null || isDropIntoSelf(dest, localPaths)) return;
    } else {
      final aim = _resolveOsCanvasDropAim(
        viewModel,
        event.position.global,
        localPaths,
        anchorPath: fileTileLocalDragAnchor(event.session),
        vacateSources: isCut,
      );
      if (aim == null) return;
      dest = aim.folderPath ?? viewModel.currentDirectory;
      at = aim.cell;
      placements = aim.placements;
    }

    _pendingDropPaths = snapshot.paths;
    _pendingDropCut = isCut;
    _pendingDropDest = dest;
    _pendingDropAt = at;
    _pendingDropPlacements = placements;

    try {
      await viewModel.importPaths(
        snapshot.paths,
        isCut: isCut,
        at: at,
        destDir: dest,
        placements: placements,
      );
    } on MoveConflictException catch (e) {
      if (!mounted) return;
      await _showNameConflictDialog(
        context,
        names: e.attemptedNames.isNotEmpty
            ? e.attemptedNames.toSet()
            : snapshot.paths.map(p.basename).toSet(),
        targetPath: e.targetPath,
        conflictingNames: e.conflictingNames,
        onSkip: () => viewModel.importPaths(
          _pendingDropPaths,
          isCut: _pendingDropCut,
          at: _pendingDropAt,
          destDir: _pendingDropDest,
          placements: _pendingDropPlacements,
          skipConflicts: true,
        ),
      );
    }
  }

  void _listenForOsDragOut(
    DragSession session,
    List<String> paths,
    DragOutSnapshot snapshot,
  ) {
    void listener() {
      session.dragCompleted.removeListener(listener);
      final op = session.dragCompleted.value;
      debugPrint(
          '[os-drag-out] done op=$op local=$_osDragOutDropWasLocal files=${paths.length}');
      if (!mounted) {
        unawaited(snapshot.discard());
        return;
      }
      if (_osDragOutDropWasLocal) {
        _osDragOutDropWasLocal = false;
        unawaited(snapshot.discard());
        return;
      }
      unawaited(context.read<DesktopViewModel>().finalizeExternalMove(
            paths,
            deleteIfPresent: op == DropOperation.move,
            restoreTaken: snapshot.putBack,
            releaseUnused: snapshot.discard,
          ));
    }

    session.dragCompleted.addListener(listener);
  }

  Widget _osDropRegion({
    required DesktopViewModel viewModel,
    required bool breadcrumbs,
    required Widget child,
  }) {
    return DropRegion(
      formats: osFileDropFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: (_) => _osDropEnter(viewModel),
      onDropLeave: (_) => _osDropLeave(viewModel, breadcrumbs: breadcrumbs),
      onDropEnded: (_) => _osDropEnded(viewModel, breadcrumbs: breadcrumbs),
      onDropOver: (event) =>
          _onOsDropOver(event, viewModel, breadcrumbs: breadcrumbs),
      onPerformDrop: (event) =>
          _onOsPerformDrop(event, viewModel, breadcrumbs: breadcrumbs),
      child: child,
    );
  }

  /// Rename and new-file fields keep their own text undo.
  bool _isTextInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final viewModel = context.read<DesktopViewModel>();
    final modifiers = ClickModifiers.fromHardwareKeyboard();
    final action = viewModel.bindings.resolveKey(event.logicalKey, modifiers);

    switch (action) {
      case ControlAction.copy:
        if (viewModel.selectedNodeNames.isEmpty) {
          return KeyEventResult.ignored;
        }
        viewModel.copySelection();
        return KeyEventResult.handled;
      case ControlAction.cut:
        if (viewModel.selectedNodeNames.isEmpty) {
          return KeyEventResult.ignored;
        }
        viewModel.cutSelection();
        return KeyEventResult.handled;
      case ControlAction.paste:
        _pasteFromShortcut(viewModel);
        return KeyEventResult.handled;
      case ControlAction.undo:
        if (_isTextInputFocused()) return KeyEventResult.ignored;
        viewModel.undo();
        return KeyEventResult.handled;
      case ControlAction.redo:
        if (_isTextInputFocused()) return KeyEventResult.ignored;
        viewModel.redo();
        return KeyEventResult.handled;
      case ControlAction.delete:
        if (viewModel.selectedNodeNames.isEmpty) {
          return KeyEventResult.ignored;
        }
        _confirmDeleteSelected(context, viewModel);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // Deferred: directory search.
  // void _openSearchBar() {
  //   setState(() => _searchBarOpen = true);
  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     _searchFocusNode.requestFocus();
  //   });
  // }

  Future<void> _pasteFromShortcut(DesktopViewModel viewModel) async {
    try {
      await viewModel.paste();
    } on MoveConflictException catch (e) {
      if (!mounted) return;
      await _showNameConflictDialog(
        context,
        names: e.attemptedNames.isNotEmpty
            ? e.attemptedNames.toSet()
            : viewModel.clipboard?.names.toSet() ?? {},
        targetPath: e.targetPath,
        conflictingNames: e.conflictingNames,
        onSkip: () => viewModel.paste(skipConflicts: true),
      );
    }
  }

  Future<void> _pasteAt(
      DesktopViewModel viewModel, Offset logicalPosition) async {
    final snappedPos = viewModel.coords.snapToCellCorner(logicalPosition);
    try {
      final pasted = await viewModel.paste(at: snappedPos);
      if (!pasted) throw StateError('Nothing to paste');
    } on MoveConflictException catch (e) {
      if (!mounted) return;
      await _showNameConflictDialog(
        context,
        names: e.attemptedNames.isNotEmpty
            ? e.attemptedNames.toSet()
            : viewModel.clipboard?.names.toSet() ?? {},
        targetPath: e.targetPath,
        conflictingNames: e.conflictingNames,
        onSkip: () => viewModel.paste(at: snappedPos, skipConflicts: true),
      );
      rethrow;
    }
  }

  /// OS drag image for a multi-selection: every dragged tile, laid out the
  /// way it sits on the canvas, with the grabbed tile kept under the pointer.
  Widget? _selectionDragImage(DesktopViewModel viewModel, DesktopNode anchor) {
    if (!viewModel.isNodeSelected(anchor.name) ||
        viewModel.selectedNodeNames.length < 2) {
      return null;
    }
    final nodes = [
      for (final node in viewModel.nodes)
        if (viewModel.selectedNodeNames.contains(node.name) &&
            node.name != MetadataManager.fileName)
          node,
    ];
    if (nodes.length < 2 || !nodes.any((n) => n.name == anchor.name)) {
      return null;
    }

    final scale = viewModel.scale;
    final cell = GridConfig.gridCellSize * scale;
    var minX = nodes.first.position.dx;
    var minY = nodes.first.position.dy;
    var maxX = minX;
    var maxY = minY;
    for (final node in nodes) {
      minX = math.min(minX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxX = math.max(maxX, node.position.dx);
      maxY = math.max(maxY, node.position.dy);
    }
    final width = (maxX - minX) * scale + cell;
    final height = (maxY - minY) * scale + cell;
    // A snapshot this large fails to encode and freezes the drag start.
    const maxExtent = 4096.0;
    if (width > maxExtent || height > maxExtent) return null;

    final anchorPos = nodes.firstWhere((n) => n.name == anchor.name).position;
    final anchorInImage = Offset(
      (anchorPos.dx - minX) * scale,
      (anchorPos.dy - minY) * scale,
    );
    final ordered = [
      for (final node in nodes)
        if (node.name != anchor.name) node,
      nodes.firstWhere((n) => n.name == anchor.name),
    ];

    return SnapshotSettings(
      translation: (rect, dragPosition) => -anchorInImage,
      constraintsTransform: (constraints) =>
          BoxConstraints.tightFor(width: width, height: height),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final node in ordered)
              Positioned(
                left: (node.position.dx - minX) * scale,
                top: (node.position.dy - minY) * scale,
                child: Opacity(
                  opacity: viewModel.isCutPending(node.name) ? 0.45 : 1,
                  child: _DesktopNodeWidget(
                    node: node,
                    scale: scale,
                    gridSize: GridConfig.gridCellSize,
                    directoryColor: viewModel.directoryColor,
                    fileColor: viewModel.fileColor,
                    isSelected: true,
                    icon:
                        iconForEntry(node.name, isDirectory: node.isDirectory),
                    thumbnail: viewModel.thumbnailCache.imageFor(
                      p.join(viewModel.currentDirectory, node.name),
                    ),
                    visibleBorders: _previewBorders(node, nodes, viewModel),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Set<_BorderSide> _previewBorders(
    DesktopNode node,
    List<DesktopNode> cohort,
    DesktopViewModel viewModel,
  ) {
    Color colorOf(DesktopNode n) =>
        n.color ??
        (n.isDirectory ? viewModel.directoryColor : viewModel.fileColor);
    final nodeColor = colorOf(node);
    final positions = <Offset>[node.position];
    for (final other in cohort) {
      if (other.name == node.name) continue;
      if (colorOf(other) != nodeColor) continue;
      positions.add(other.position);
    }
    final outer = outerCellOutlineSides(
      node.position,
      positions,
      GridConfig.gridCellSize,
    );
    return {
      if (outer.contains(CellOutlineSide.top)) _BorderSide.top,
      if (outer.contains(CellOutlineSide.right)) _BorderSide.right,
      if (outer.contains(CellOutlineSide.bottom)) _BorderSide.bottom,
      if (outer.contains(CellOutlineSide.left)) _BorderSide.left,
    };
  }

  Set<_BorderSide> _getVisibleBorders(
      DesktopNode node, DesktopViewModel viewModel) {
    const all = {
      _BorderSide.top,
      _BorderSide.right,
      _BorderSide.bottom,
      _BorderSide.left,
    };
    if (!viewModel.isNodeSelected(node.name)) return all;

    final nodeColor = node.color ??
        (node.isDirectory ? viewModel.directoryColor : viewModel.fileColor);
    final cohort = <Offset>[node.position];
    for (final neighbor in viewModel.nodes) {
      if (neighbor.name == node.name) continue;
      if (!viewModel.isNodeSelected(neighbor.name)) continue;
      final neighborColor = neighbor.color ??
          (neighbor.isDirectory
              ? viewModel.directoryColor
              : viewModel.fileColor);
      if (neighborColor != nodeColor) continue;
      cohort.add(neighbor.position);
    }

    final outer = outerCellOutlineSides(
      node.position,
      cohort,
      GridConfig.gridCellSize,
    );
    return {
      if (outer.contains(CellOutlineSide.top)) _BorderSide.top,
      if (outer.contains(CellOutlineSide.right)) _BorderSide.right,
      if (outer.contains(CellOutlineSide.bottom)) _BorderSide.bottom,
      if (outer.contains(CellOutlineSide.left)) _BorderSide.left,
    };
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<DesktopViewModel>();
    final colors = Theme.of(context).extension<FileTileColors>()!;

    final error = viewModel.lastError;
    if (error != null) {
      viewModel.clearError();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(SnackBar(content: Text(error)));
        }
      });
    }

    final layoutIssue = viewModel.layoutIssue;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        toolbarHeight: AppConfig.appBarHeight,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 18),
              onPressed: viewModel.canGoBack ? viewModel.back : null,
              tooltip: 'Back',
              color: viewModel.canGoBack
                  ? colors.textPrimary
                  : colors.iconDisabled,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 18),
              onPressed: viewModel.canGoForward ? viewModel.forward : null,
              tooltip: 'Forward',
              color: viewModel.canGoForward
                  ? colors.textPrimary
                  : colors.iconDisabled,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: viewModel.navigateUp,
              tooltip: 'Go Up',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _osDropRegion(
                viewModel: viewModel,
                breadcrumbs: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _buildBreadcrumbs(viewModel),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => viewModel.refresh(),
            tooltip: 'Refresh',
          ),
          // Deferred: directory search.
          // IconButton(
          //   icon: const Icon(Icons.search),
          //   onPressed: _openSearchBar,
          //   tooltip: 'Search',
          // ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsModal(context, viewModel),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (layoutIssue != null) _LayoutIssueBanner(issue: layoutIssue),
          // Deferred: directory search.
          // if (_searchBarOpen) _buildSearchBar(viewModel, colors),
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _canvasSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  _updateVisibleThumbnails(viewModel, constraints);
                  return _osDropRegion(
                    viewModel: viewModel,
                    breadcrumbs: false,
                    child: Listener(
                      key: _canvasKey,
                      onPointerDown: (event) {
                        _clickHandler.bindings = viewModel.bindings;
                        // Adjust click position from window to canvas coordinates
                        final canvasPosition = _globalToCanvas(event.position);

                        // Build hit test nodes once for both left and right clicks
                        final nodes = viewModel.nodes.map((node) {
                          return HitTestNode(
                            id: node.name,
                            position: node.position,
                            size: GridConfig.gridCellSize,
                          );
                        }).toList();

                        // Handle left-click on empty canvas (deselect all).
                        // Clicks that hit a node are handled by that node's own GestureDetector
                        // (onTap/onPanDown), so its tap-vs-drag arena can decide what to do.
                        if (event.buttons & kPrimaryButton != 0) {
                          final hitNode = nodes.any((n) =>
                              n.hitsPoint(canvasPosition, viewModel.coords));
                          if (!hitNode) {
                            _clickHandler.handlePrimaryPointerDown(
                              screenPosition: canvasPosition,
                              nodes: nodes,
                              coords: viewModel.coords,
                            );
                          }
                        }
                        // Handle right-click for context menu (apply immediately)
                        else if (event.buttons & kSecondaryButton != 0) {
                          final result =
                              _clickHandler.handleSecondaryPointerDown(
                            screenPosition: canvasPosition,
                            nodes: nodes,
                            coords: viewModel.coords,
                          );

                          switch (result) {
                            case NodeClickResult():
                              // Click handler already selected the node
                              _showNodeContextMenu(
                                  context, event.position, viewModel);
                            case BackgroundClickResult():
                              _showBackgroundContextMenu(
                                  context,
                                  event.position,
                                  result.logicalPosition,
                                  viewModel);
                          }
                        }
                      },
                      onPointerSignal: (pointerSignal) {
                        if (pointerSignal is PointerScrollEvent) {
                          final modifiers =
                              ClickModifiers.fromHardwareKeyboard();
                          final scrollAction =
                              viewModel.bindings.resolveScroll(modifiers);

                          if (scrollAction == ControlAction.panVertical) {
                            final delta = viewModel.invertVerticalScroll
                                ? -pointerSignal.scrollDelta.dy
                                : pointerSignal.scrollDelta.dy;
                            viewModel.offset =
                                viewModel.offset + Offset(0, delta);
                          } else if (scrollAction ==
                              ControlAction.panHorizontal) {
                            final delta = viewModel.invertHorizontalScroll
                                ? -pointerSignal.scrollDelta.dy
                                : pointerSignal.scrollDelta.dy;
                            viewModel.offset =
                                viewModel.offset + Offset(delta, 0);
                          } else if (scrollAction == ControlAction.zoom) {
                            final cursorScreenPos =
                                _globalToCanvas(pointerSignal.position);

                            final logicalUnderCursor = viewModel.coords
                                .screenToLogical(cursorScreenPos);

                            double zoomFactor = 1.1;
                            double newScale = viewModel.scale;
                            if (pointerSignal.scrollDelta.dy > 0) {
                              newScale /= zoomFactor;
                            } else {
                              newScale *= zoomFactor;
                            }
                            newScale = newScale.clamp(0.1, 10.0);

                            final newOffset = cursorScreenPos -
                                (logicalUnderCursor * newScale);

                            viewModel.scale = newScale;
                            viewModel.offset = newOffset;
                          }
                        }
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanDown: (details) {
                                // Covers both canvas panning and the selection box below -
                                // either way, suspend polling for the whole gesture so a
                                // background reload can't fight with it.
                                viewModel.beginInteraction();
                                if (viewModel.bindings.isSelectionBoxModifiers(
                                    ClickModifiers.fromHardwareKeyboard())) {
                                  setState(() {
                                    _selectionBoxStart = details.localPosition;
                                    _selectionBoxEnd = details.localPosition;
                                  });
                                }
                              },
                              onPanUpdate: (details) {
                                if (_selectionBoxStart != null) {
                                  setState(() {
                                    _selectionBoxEnd = details.localPosition;
                                  });
                                } else {
                                  viewModel.offset =
                                      viewModel.offset + details.delta;
                                }
                              },
                              onPanCancel: () {
                                viewModel.endInteraction();
                                if (_selectionBoxStart != null) {
                                  setState(() {
                                    _selectionBoxStart = null;
                                    _selectionBoxEnd = null;
                                  });
                                }
                              },
                              onPanEnd: (details) {
                                viewModel.endInteraction();
                                if (_selectionBoxStart != null &&
                                    _selectionBoxEnd != null) {
                                  final selectedNodeIds =
                                      _getNodesInSelectionBox(
                                          _selectionBoxStart!,
                                          _selectionBoxEnd!);
                                  if (selectedNodeIds.isNotEmpty) {
                                    viewModel.selectionController
                                        .rangeSelect(selectedNodeIds);
                                  } else {
                                    viewModel.selectionController
                                        .clearSelection();
                                  }
                                  setState(() {
                                    _selectionBoxStart = null;
                                    _selectionBoxEnd = null;
                                  });
                                }
                              },
                              child: ClipRect(
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: GridPainter(
                                    offset: viewModel.offset,
                                    scale: viewModel.scale,
                                    lineColor: colors.gridLine,
                                    originLineColor: colors.gridLineOrigin,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_selectionBoxStart != null &&
                              _selectionBoxEnd != null)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: SelectionBoxPainter(
                                    start: _selectionBoxStart!,
                                    end: _selectionBoxEnd!,
                                  ),
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: PlacementRegionPainter(
                                  config: viewModel.newElementPlacementConfig,
                                  coords: viewModel.coords,
                                ),
                              ),
                            ),
                          ),
                          ...viewModel.orderedNodes.map((node) {
                            final screenPos =
                                viewModel.coords.logicalToScreen(node.position);
                            final isSelected =
                                viewModel.isNodeSelected(node.name);
                            final visibleBorders =
                                _getVisibleBorders(node, viewModel);
                            final isLayoutFile =
                                node.name == MetadataManager.fileName;
                            final nodeChild = GestureDetector(
                              onTap: () {
                                _clickHandler.bindings = viewModel.bindings;
                                final hitTestNodes = viewModel.nodes.map((n) {
                                  return HitTestNode(
                                    id: n.name,
                                    position: n.position,
                                    size: GridConfig.gridCellSize,
                                  );
                                }).toList();
                                _clickHandler.handleNodeTap(
                                    nodeId: node.name, nodes: hitTestNodes);
                              },
                              onDoubleTap: node.isDirectory
                                  ? () => viewModel.loadDirectory(p.join(
                                      viewModel.currentDirectory, node.name))
                                  : () =>
                                      viewModel.openSystemDefault(node.name),
                              onPanDown: isLayoutFile
                                  ? (details) {
                                      viewModel.startDrag({node.name});
                                      final canvas = _globalToCanvas(
                                          details.globalPosition);
                                      _layoutGrabInCanvas = viewModel.coords
                                              .logicalToScreen(node.position) -
                                          canvas;
                                      _layoutDragName = node.name;
                                      _edgeScrollCursor =
                                          details.globalPosition;
                                    }
                                  : null,
                              onPanUpdate: isLayoutFile
                                  ? (details) {
                                      _armLayoutEdgeScroll(
                                          details.globalPosition);
                                      _pinLayoutFileToCursor(viewModel);
                                    }
                                  : null,
                              onPanEnd: isLayoutFile
                                  ? (_) {
                                      _stopLayoutEdgeScroll();
                                      viewModel
                                          .completeOrRevertDrag({node.name});
                                    }
                                  : null,
                              onPanCancel: isLayoutFile
                                  ? () {
                                      _stopLayoutEdgeScroll();
                                      viewModel.cancelDrag();
                                    }
                                  : null,
                              child: Opacity(
                                opacity: viewModel.isCutPending(node.name)
                                    ? 0.45
                                    : 1,
                                child: _DesktopNodeWidget(
                                  node: node,
                                  scale: viewModel.scale,
                                  gridSize: GridConfig.gridCellSize,
                                  directoryColor: viewModel.directoryColor,
                                  fileColor: viewModel.fileColor,
                                  isSelected: isSelected,
                                  icon: iconForEntry(node.name,
                                      isDirectory: node.isDirectory),
                                  thumbnail: viewModel.thumbnailCache.imageFor(
                                      p.join(viewModel.currentDirectory,
                                          node.name)),
                                  // Deferred: directory search.
                                  // isSearchMatch:
                                  //     viewModel.isSearchMatch(node.name),
                                  visibleBorders: visibleBorders,
                                  isDragTarget:
                                      _dragTargetNodeName == node.name,
                                ),
                              ),
                            );
                            return Positioned(
                              key: ValueKey(node.name),
                              left: screenPos.dx,
                              top: screenPos.dy,
                              child: isLayoutFile
                                  ? nodeChild
                                  : DragItemWidget(
                                      dragItemProvider: (request) async {
                                        final namesToDrag =
                                            viewModel.isNodeSelected(
                                                        node.name) &&
                                                    viewModel.selectedNodeNames
                                                            .length >
                                                        1
                                                ? viewModel.selectedNodeNames
                                                : {node.name};
                                        final paths = [
                                          for (final name in namesToDrag)
                                            if (name !=
                                                MetadataManager.fileName)
                                              p.join(viewModel.currentDirectory,
                                                  name)
                                        ];
                                        if (paths.isEmpty) return null;
                                        final snapshot =
                                            await DragOutSnapshot.capture(
                                                paths);
                                        if (!mounted) {
                                          await snapshot.discard();
                                          return null;
                                        }
                                        _osDragOutDropWasLocal = false;
                                        _listenForOsDragOut(
                                            request.session, paths, snapshot);
                                        final copy = HardwareKeyboard
                                            .instance.isControlPressed;
                                        debugPrint(
                                            '[os-drag-out] start copy=$copy files=${paths.length}');
                                        final item = DragItem(
                                          suggestedName:
                                              p.basename(paths.first),
                                          localData: {
                                            fileTileDragLocalKey: true,
                                            fileTileDragLocalPathsKey: paths,
                                            fileTileDragLocalAnchorKey: p.join(
                                                viewModel.currentDirectory,
                                                node.name),
                                            fileTileDragLocalCutKey: !copy,
                                          },
                                        );
                                        item.add(gnomeCopiedFilesFormat(
                                            encodeGnomeCopiedFiles(paths,
                                                isCut: !copy)));
                                        item.add(fileUriListFormat(
                                            encodeFileUriList(paths)));
                                        return item;
                                      },
                                      allowedOperations: () =>
                                          osFileDragOutOperations(
                                        controlPressed: HardwareKeyboard
                                            .instance.isControlPressed,
                                      ),
                                      dragBuilder: (context, child) =>
                                          _selectionDragImage(viewModel, node),
                                      child: DraggableWidget(child: nodeChild),
                                    ),
                            );
                          }),
                          if (_osDropCells.isNotEmpty &&
                              _osDropAnchorCell != null)
                            Positioned.fill(
                              child: OsDropTargetOverlay(
                                cells: _osDropCells,
                                anchor: _osDropAnchorCell!,
                                coords: viewModel.coords,
                                color: colors.accent,
                              ),
                            ),
                          if (viewModel.isLoading && viewModel.nodes.isEmpty)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            ),
                          if (viewModel.isSwitchingMetadataBackend)
                            const _SwitchingLayoutStorageOverlay(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleContextMenuShiftDragStart(Offset globalPos) {
    final canvasPosition = _globalToCanvas(globalPos);
    setState(() {
      _selectionBoxStart = canvasPosition;
      _selectionBoxEnd = canvasPosition;
    });
  }

  void _handleContextMenuShiftDragUpdate(Offset globalPos) {
    final canvasPosition = _globalToCanvas(globalPos);
    setState(() {
      _selectionBoxEnd = canvasPosition;
    });
  }

  void _handleContextMenuShiftDragEnd(DesktopViewModel viewModel) {
    if (_selectionBoxStart != null && _selectionBoxEnd != null) {
      final selectedNodeIds =
          _getNodesInSelectionBox(_selectionBoxStart!, _selectionBoxEnd!);
      if (selectedNodeIds.isNotEmpty) {
        viewModel.selectionController.rangeSelect(selectedNodeIds);
      } else {
        viewModel.selectionController.clearSelection();
      }
    }
    setState(() {
      _selectionBoxStart = null;
      _selectionBoxEnd = null;
    });
  }

  void _showBackgroundContextMenu(BuildContext context, Offset globalPosition,
      Offset logicalPosition, DesktopViewModel viewModel) {
    CascadingMenu.show(
      context,
      position: globalPosition,
      onBarrierLeftTapped: (globalPos) {
        final canvasPosition = _globalToCanvas(globalPos);
        final nodes = viewModel.nodes.map((node) {
          return HitTestNode(
            id: node.name,
            position: node.position,
            size: GridConfig.gridCellSize,
          );
        }).toList();
        _clickHandler.handlePrimaryPointerDown(
          screenPosition: canvasPosition,
          nodes: nodes,
          coords: viewModel.coords,
        );
      },
      onBarrierRightTapped: (globalPos) {
        final canvasPosition = _globalToCanvas(globalPos);
        final nodes = viewModel.nodes.map((node) {
          return HitTestNode(
            id: node.name,
            position: node.position,
            size: GridConfig.gridCellSize,
          );
        }).toList();
        final result = _clickHandler.handleSecondaryPointerDown(
          screenPosition: canvasPosition,
          nodes: nodes,
          coords: viewModel.coords,
        );
        switch (result) {
          case NodeClickResult(nodeId: final nodeId):
            if (!viewModel.isNodeSelected(nodeId)) {
              viewModel.selectionController.selectSingle(nodeId);
            }
            _showNodeContextMenu(context, globalPos, viewModel);
          case BackgroundClickResult():
            _showBackgroundContextMenu(
                context, globalPos, result.logicalPosition, viewModel);
        }
      },
      onBarrierShiftDragStart: _handleContextMenuShiftDragStart,
      onBarrierShiftDragUpdate: _handleContextMenuShiftDragUpdate,
      onBarrierShiftDragEnd: () => _handleContextMenuShiftDragEnd(viewModel),
      isSelectionBoxGesture: (event) =>
          event.buttons & kPrimaryButton != 0 &&
          viewModel.bindings
              .isSelectionBoxModifiers(ClickModifiers.fromHardwareKeyboard()),
      items: [
        CascadingMenuItem(
          label: 'New Folder',
          icon: Icons.create_new_folder,
          onTap: () {
            final snappedPos =
                viewModel.coords.snapToCellCorner(logicalPosition);
            final (gridX, gridY) =
                viewModel.coords.logicalPosToGridIndices(snappedPos);
            debugPrint(
                '[CREATE FOLDER] logical: (${logicalPosition.dx.toStringAsFixed(1)}, ${logicalPosition.dy.toStringAsFixed(1)}) | snapped: (${snappedPos.dx.toStringAsFixed(1)}, ${snappedPos.dy.toStringAsFixed(1)}) | grid: ($gridX, $gridY)');
            _promptCreate(context, viewModel,
                isDirectory: true,
                gridPosition: snappedPos,
                originalLogicalPos: logicalPosition);
          },
        ),
        CascadingMenuItem(
          label: 'New File',
          icon: Icons.note_add,
          onTap: () {
            final snappedPos =
                viewModel.coords.snapToCellCorner(logicalPosition);
            _promptCreate(context, viewModel,
                isDirectory: false,
                gridPosition: snappedPos,
                originalLogicalPos: logicalPosition);
          },
        ),
        CascadingMenuItem(
          label: 'New Symlink',
          icon: Icons.link,
          onTap: () {
            final snappedPos =
                viewModel.coords.snapToCellCorner(logicalPosition);
            _promptCreateSymlink(context, viewModel,
                gridPosition: snappedPos, originalLogicalPos: logicalPosition);
          },
        ),
        CascadingMenuItem.divider(),
        ..._openInTerminalMenuItems(
          viewModel,
          workingDirectory: viewModel.currentDirectory,
        ),
        CascadingMenuItem.divider(),
        CascadingMenuItem(
          label: 'Paste',
          icon: Icons.paste,
          flashConfirm: true,
          onTap: () => _pasteAt(viewModel, logicalPosition),
        ),
        CascadingMenuItem(
          label: 'Refresh',
          icon: Icons.refresh,
          onTap: () => viewModel.refresh(),
        ),
      ],
    );
  }

  void _showNodeContextMenu(
      BuildContext context, Offset position, DesktopViewModel viewModel) {
    final selectedNodes = viewModel.selectedNodeNames
        .map((name) => viewModel.nodes.firstWhere((n) => n.name == name))
        .toList();
    if (selectedNodes.isEmpty) return;
    final node = selectedNodes.first;
    final extension = p.extension(node.name).toLowerCase();
    final isBash = extension == '.sh';
    final isPython = extension == '.py';
    final isNode = extension == '.js' ||
        extension == '.mjs' ||
        extension == '.cjs' ||
        extension == '.ts';
    final available = viewModel.appRegistry
        .where((app) => viewModel.availableApps[app['cmd']] == true)
        .toList();

    final items = <CascadingMenuItem>[
      CascadingMenuItem(
        label: 'Open',
        icon: node.isDirectory ? Icons.folder_open : Icons.open_in_new,
        onTap: node.isDirectory
            ? () => viewModel
                .loadDirectory(p.join(viewModel.currentDirectory, node.name))
            : () => viewModel.openSystemDefault(node.name),
      ),
      CascadingMenuItem(
        label: 'Open With...',
        icon: Icons.apps,
        children: [
          CascadingMenuItem(
            label: 'System Default',
            icon: Icons.settings_suggest,
            onTap: () => viewModel.openSystemDefault(node.name),
          ),
          if (available.isNotEmpty) CascadingMenuItem.divider(),
          ...available.map((app) => CascadingMenuItem(
                label: app['name']!,
                icon: _getIconData(app['icon']!),
                onTap: () => viewModel.openWith(app['cmd']!, node.name),
              )),
        ],
      ),
      if (node.isDirectory)
        ..._openInTerminalMenuItems(
          viewModel,
          workingDirectory: viewModel.terminalDirectoryForNode(node),
        ),
      CascadingMenuItem(
        label: 'Rename',
        icon: Icons.edit,
        onTap: () => _promptRename(
            context, viewModel, node, () => Navigator.pop(context)),
      ),
      if (!node.isDirectory && (isBash || isPython || isNode)) ...[
        CascadingMenuItem.divider(),
        if (isBash)
          CascadingMenuItem(
            label: 'Bash Script',
            icon: Icons.terminal,
            children: [
              CascadingMenuItem(
                label: 'Capture Output (Dialog)',
                icon: Icons.output,
                onTap: () => _runScript(context, viewModel, 'bash', node.name),
              ),
              CascadingMenuItem(
                label: 'Run in Terminal (Interactive)',
                icon: Icons.terminal,
                onTap: () => viewModel.runInTerminal('bash', node.name),
              ),
            ],
          ),
        if (isPython)
          CascadingMenuItem(
            label: 'Python Script',
            icon: Icons.code,
            children: [
              CascadingMenuItem(
                label: 'Capture Output (Dialog)',
                icon: Icons.output,
                onTap: () =>
                    _runScript(context, viewModel, 'python3', node.name),
              ),
              CascadingMenuItem(
                label: 'Run in Terminal (Interactive)',
                icon: Icons.terminal,
                onTap: () => viewModel.runInTerminal('python3', node.name),
              ),
            ],
          ),
        if (isNode)
          CascadingMenuItem(
            label: 'Node.js Script',
            icon: Icons.javascript,
            children: [
              CascadingMenuItem(
                label: 'Capture Output (Dialog)',
                icon: Icons.output,
                onTap: () => _runScript(context, viewModel, 'node', node.name),
              ),
              CascadingMenuItem(
                label: 'Run in Terminal (Interactive)',
                icon: Icons.terminal,
                onTap: () => viewModel.runInTerminal('node', node.name),
              ),
            ],
          ),
      ],
      CascadingMenuItem.divider(),
      CascadingMenuItem(
        label: 'Change Color',
        icon: Icons.palette,
        children: [
          CascadingMenuItem(
            label: 'Default',
            onTap: () => viewModel.updateNodeColor(node.name, null),
          ),
          CascadingMenuItem.divider(),
          CascadingMenuItem(
            label: 'Red',
            onTap: () => viewModel.updateNodeColor(node.name, Colors.redAccent),
          ),
          CascadingMenuItem(
            label: 'Green',
            onTap: () =>
                viewModel.updateNodeColor(node.name, Colors.greenAccent),
          ),
          CascadingMenuItem(
            label: 'Blue',
            onTap: () =>
                viewModel.updateNodeColor(node.name, Colors.blueAccent),
          ),
          CascadingMenuItem(
            label: 'Orange',
            onTap: () =>
                viewModel.updateNodeColor(node.name, Colors.orangeAccent),
          ),
          CascadingMenuItem(
            label: 'Purple',
            onTap: () =>
                viewModel.updateNodeColor(node.name, Colors.purpleAccent),
          ),
          CascadingMenuItem(
            label: 'Pink',
            onTap: () =>
                viewModel.updateNodeColor(node.name, Colors.pinkAccent),
          ),
          CascadingMenuItem(
            label: 'Teal',
            onTap: () =>
                viewModel.updateNodeColor(node.name, Colors.tealAccent),
          ),
        ],
      ),
      CascadingMenuItem.divider(),
      CascadingMenuItem(
        label: 'Copy',
        icon: Icons.copy,
        flashConfirm: true,
        onTap: () => viewModel.copySelection(),
      ),
      CascadingMenuItem(
        label: 'Cut',
        icon: Icons.content_cut,
        flashConfirm: true,
        onTap: () => viewModel.cutSelection(),
      ),
      CascadingMenuItem.divider(),
      CascadingMenuItem(
        label: 'Delete',
        icon: Icons.delete,
        textColor: Colors.redAccent,
        iconColor: Colors.redAccent,
        onTap: () {
          Navigator.pop(context);
          _confirmDeleteSelected(context, viewModel);
        },
      ),
    ];

    CascadingMenu.show(
      context,
      position: position,
      onBarrierLeftTapped: (globalPos) {
        final canvasPosition = _globalToCanvas(globalPos);
        final nodes = viewModel.nodes.map((node) {
          return HitTestNode(
            id: node.name,
            position: node.position,
            size: GridConfig.gridCellSize,
          );
        }).toList();
        _clickHandler.handlePrimaryPointerDown(
          screenPosition: canvasPosition,
          nodes: nodes,
          coords: viewModel.coords,
        );
      },
      onBarrierRightTapped: (globalPos) {
        final canvasPosition = _globalToCanvas(globalPos);
        final nodes = viewModel.nodes.map((node) {
          return HitTestNode(
            id: node.name,
            position: node.position,
            size: GridConfig.gridCellSize,
          );
        }).toList();
        final result = _clickHandler.handleSecondaryPointerDown(
          screenPosition: canvasPosition,
          nodes: nodes,
          coords: viewModel.coords,
        );
        switch (result) {
          case NodeClickResult(nodeId: final nodeId):
            if (!viewModel.isNodeSelected(nodeId)) {
              viewModel.selectionController.selectSingle(nodeId);
            }
            _showNodeContextMenu(context, globalPos, viewModel);
          case BackgroundClickResult():
            _showBackgroundContextMenu(
                context, globalPos, result.logicalPosition, viewModel);
        }
      },
      onBarrierShiftDragStart: _handleContextMenuShiftDragStart,
      onBarrierShiftDragUpdate: _handleContextMenuShiftDragUpdate,
      onBarrierShiftDragEnd: () => _handleContextMenuShiftDragEnd(viewModel),
      isSelectionBoxGesture: (event) =>
          event.buttons & kPrimaryButton != 0 &&
          viewModel.bindings
              .isSelectionBoxModifiers(ClickModifiers.fromHardwareKeyboard()),
      items: items,
    );
  }

  Future<void> _promptCreate(BuildContext context, DesktopViewModel viewModel,
      {required bool isDirectory,
      Offset? gridPosition,
      Offset? originalLogicalPos}) async {
    final controller = TextEditingController();
    final type = isDirectory ? 'Folder' : 'File';
    final colors = Theme.of(context).extension<FileTileColors>()!;

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('New $type', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: colors.textDim),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.borderSubtle)),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              if (isDirectory) {
                viewModel.createDirectory(value,
                    gridPosition: gridPosition,
                    originalLogicalPos: originalLogicalPos);
              } else {
                viewModel.createFile(value,
                    gridPosition: gridPosition,
                    originalLogicalPos: originalLogicalPos);
              }
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                if (isDirectory) {
                  viewModel.createDirectory(controller.text,
                      gridPosition: gridPosition,
                      originalLogicalPos: originalLogicalPos);
                } else {
                  viewModel.createFile(controller.text,
                      gridPosition: gridPosition,
                      originalLogicalPos: originalLogicalPos);
                }
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptCreateSymlink(
      BuildContext context, DesktopViewModel viewModel,
      {Offset? gridPosition, Offset? originalLogicalPos}) async {
    final nameController = TextEditingController();
    final colors = Theme.of(context).extension<FileTileColors>()!;
    final picker = LinuxFilePicker();
    String? targetPath;
    String? suggestedName;
    String? pickerError;

    return showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          void applyTarget(String path) {
            final base = p.basename(path);
            if (nameController.text.isEmpty ||
                nameController.text == suggestedName) {
              nameController.text = base;
              suggestedName = base;
            }
            targetPath = path;
            pickerError = null;
          }

          String pickerStart() {
            final current = targetPath;
            if (current == null || current.isEmpty) {
              return viewModel.currentDirectory;
            }
            return p.dirname(current);
          }

          Future<void> choose(Future<String?> Function() pick) async {
            try {
              final path = await pick();
              if (!context.mounted || path == null || path.isEmpty) return;
              setState(() => applyTarget(path));
            } catch (e) {
              debugPrint('File picker failed: $e');
              if (!context.mounted) return;
              setState(() => pickerError = "Couldn't open the file picker");
            }
          }

          void submit() {
            final name = nameController.text;
            final target = targetPath;
            if (name.isEmpty || target == null || target.isEmpty) return;
            viewModel.createSymlink(name, target,
                gridPosition: gridPosition,
                originalLogicalPos: originalLogicalPos);
            Navigator.pop(dialogContext);
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20.0),
            backgroundColor: colors.surface,
            title: Text('New Symlink',
                style: TextStyle(color: colors.textPrimary)),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.33,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Link name',
                      hintStyle: TextStyle(color: colors.textDim),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colors.borderSubtle)),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    targetPath ?? 'No target selected',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: targetPath == null
                          ? colors.textDim
                          : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => choose(() =>
                            picker.pickFile(initialDirectory: pickerStart())),
                        icon: const Icon(Icons.insert_drive_file_outlined,
                            size: 18),
                        label: const Text('Choose file'),
                      ),
                      TextButton.icon(
                        onPressed: () => choose(() => picker.pickDirectory(
                            initialDirectory: pickerStart())),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Choose folder'),
                      ),
                    ],
                  ),
                  if (pickerError != null)
                    Text(pickerError!,
                        style: const TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: submit,
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _promptRename(BuildContext context, DesktopViewModel viewModel,
      DesktopNode node, VoidCallback onConfirm) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;
    final controller = TextEditingController(text: node.name);
    final colors = Theme.of(context).extension<FileTileColors>()!;

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Rename', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(color: colors.textDim),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: colors.borderSubtle)),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty && value != node.name) {
              viewModel.renameNode(node.name, value);
              Navigator.pop(context);
              onConfirm();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty && controller.text != node.name) {
                viewModel.renameNode(node.name, controller.text);
                Navigator.pop(context);
                onConfirm();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  // Deferred: directory search.
  // Widget _buildSearchBar(DesktopViewModel viewModel, FileTileColors colors) {
  //   return Material(
  //     color: colors.surface,
  //     child: Column(
  //       mainAxisSize: MainAxisSize.min,
  //       children: [
  //         SizedBox(
  //           height: 44,
  //           child: Row(
  //             children: [
  //               const SizedBox(width: 12),
  //               Icon(Icons.search, size: 18, color: colors.textSecondary),
  //               const SizedBox(width: 8),
  //               Expanded(
  //                 child: TextField(
  //                   controller: _searchController,
  //                   focusNode: _searchFocusNode,
  //                   style: TextStyle(color: colors.textPrimary, fontSize: 14),
  //                   decoration: InputDecoration(
  //                     hintText: 'Filter this folder…',
  //                     hintStyle: TextStyle(color: colors.textDim),
  //                     border: InputBorder.none,
  //                     isDense: true,
  //                   ),
  //                   onChanged: viewModel.setSearchQuery,
  //                 ),
  //               ),
  //               FilterChip(
  //                 label: const Text('Include nested'),
  //                 selected: viewModel.searchIncludeNested,
  //                 onSelected: viewModel.setSearchIncludeNested,
  //                 visualDensity: VisualDensity.compact,
  //               ),
  //               IconButton(
  //                 icon: const Icon(Icons.close, size: 18),
  //                 tooltip: 'Close search',
  //                 onPressed: () {
  //                   _searchController.clear();
  //                   viewModel.setSearchQuery('');
  //                   viewModel.setSearchIncludeNested(false);
  //                   setState(() => _searchBarOpen = false);
  //                   _focusNode.requestFocus();
  //                 },
  //               ),
  //             ],
  //           ),
  //         ),
  //         if (viewModel.nestedSearchInProgress ||
  //             viewModel.nestedSearchHits.isNotEmpty)
  //           ConstrainedBox(
  //             constraints: const BoxConstraints(maxHeight: 200),
  //             child: ListView.builder(
  //               shrinkWrap: true,
  //               itemCount: viewModel.nestedSearchHits.length +
  //                   (viewModel.nestedSearchInProgress ? 1 : 0),
  //               itemBuilder: (context, index) {
  //                 if (viewModel.nestedSearchInProgress &&
  //                     index == viewModel.nestedSearchHits.length) {
  //                   return Padding(
  //                     padding: const EdgeInsets.all(8),
  //                     child: Text('Searching…',
  //                         style:
  //                             TextStyle(color: colors.textDim, fontSize: 12)),
  //                   );
  //                 }
  //                 final hit = viewModel.nestedSearchHits[index];
  //                 return ListTile(
  //                   dense: true,
  //                   leading: Icon(
  //                     hit.isDirectory ? Icons.folder : Icons.description,
  //                     size: 18,
  //                     color: colors.textSecondary,
  //                   ),
  //                   title: Text(hit.relativePath,
  //                       style:
  //                           TextStyle(color: colors.textPrimary, fontSize: 13)),
  //                   onTap: () => viewModel.openSearchHit(hit),
  //                 );
  //               },
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }

  List<CascadingMenuItem> _openInTerminalMenuItems(
    DesktopViewModel viewModel, {
    required String workingDirectory,
  }) {
    final terminals = viewModel.availableTerminals;
    if (terminals.length <= 1) {
      return [
        CascadingMenuItem(
          label: 'Open in Terminal',
          icon: Icons.terminal,
          onTap: () => viewModel.openInTerminal(
            workingDirectory: workingDirectory,
            terminalId: terminals.isEmpty ? null : terminals.first.id,
          ),
        ),
      ];
    }
    return [
      CascadingMenuItem(
        label: 'Open in Terminal',
        icon: Icons.terminal,
        children: terminals
            .map((app) => CascadingMenuItem(
                  label: app.id == viewModel.preferredTerminalId
                      ? '${app.name} (preferred)'
                      : app.name,
                  icon: Icons.terminal,
                  onTap: () => viewModel.openInTerminal(
                    workingDirectory: workingDirectory,
                    terminalId: app.id,
                  ),
                ))
            .toList(),
      ),
    ];
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'code':
        return Icons.code;
      case 'terminal':
        return Icons.terminal;
      case 'edit':
        return Icons.edit;
      case 'folder_open':
        return Icons.folder_open;
      default:
        return Icons.apps;
    }
  }

  Future<void> _runScript(BuildContext context, DesktopViewModel viewModel,
      String tool, String fileName) async {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Running $fileName with $tool...'),
        duration: const Duration(seconds: 1),
        backgroundColor: colors.accent,
      ),
    );

    final result = await viewModel.runScript(tool, fileName);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Result: $fileName ($tool)',
            style: TextStyle(color: colors.textPrimary, fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(
            result,
            style: TextStyle(
                color: colors.textSecondary,
                fontFamily: 'monospace',
                fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSelected(
      BuildContext context, DesktopViewModel viewModel) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;

    final selectedNames = viewModel.selectedNodeNames.toList()..sort();
    final isMultiple = selectedNames.length > 1;
    final deleteMessage = isMultiple
        ? 'Are you sure you want to delete ${selectedNames.length} items?\n\n${selectedNames.join('\n')}'
        : 'Are you sure you want to delete "${selectedNames.first}"?';
    final colors = Theme.of(context).extension<FileTileColors>()!;

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Delete', style: TextStyle(color: colors.textPrimary)),
        content: SingleChildScrollView(
          child: Text(deleteMessage,
              style: TextStyle(color: colors.textSecondary)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await viewModel.performSelectAction(DesktopSelectAction.delete);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmMetadataBackendSwitch(
    BuildContext context, {
    required MetadataBackend from,
    required MetadataBackend to,
  }) {
    final toSqlite = to == MetadataBackend.sqlite;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(toSqlite ? 'Use local database?' : 'Use JSON files?'),
        content: Text(toSqlite
            ? 'Known folder layouts will be copied into a local database. file-tile.json will be removed from those folders where possible.'
            : 'Layouts will be written back to file-tile.json in each known folder, then removed from the database where that write succeeds.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal(BuildContext context, DesktopViewModel viewModel) {
    ControlAction? capturingAction;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return ListenableBuilder(
          listenable: viewModel,
          builder: (context, _) {
            final colors = Theme.of(context).extension<FileTileColors>()!;
            final switching = viewModel.isSwitchingMetadataBackend;
            return PopScope(
              canPop: !switching,
              child: StatefulBuilder(
                builder: (context, setState) => Dialog(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.4,
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Material(
                        color: colors.surface,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text('Settings',
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Appearance
                                      Text('Appearance',
                                          style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 12)),
                                      const SizedBox(height: 12),
                                      SwitchListTile(
                                        title: Text('Dark Mode',
                                            style: TextStyle(
                                                color: colors.textPrimary)),
                                        value: viewModel.isDarkMode,
                                        onChanged: (value) {
                                          viewModel.isDarkMode = value;
                                          setState(() {});
                                        },
                                        activeThumbColor: colors.accent,
                                      ),
                                      const SizedBox(height: 16),
                                      Text('Terminal',
                                          style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 12)),
                                      const SizedBox(height: 12),
                                      if (viewModel.availableTerminals.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 16, bottom: 8),
                                          child: Text(
                                            'No terminal emulator detected',
                                            style: TextStyle(
                                                color: colors.textDim),
                                          ),
                                        )
                                      else
                                        RadioGroup<String>(
                                          groupValue: viewModel
                                                  .availableTerminals
                                                  .any((t) =>
                                                      t.id ==
                                                      viewModel
                                                          .preferredTerminalId)
                                              ? viewModel.preferredTerminalId
                                              : viewModel
                                                  .availableTerminals.first.id,
                                          onChanged: (value) {
                                            viewModel.preferredTerminalId =
                                                value;
                                            setState(() {});
                                          },
                                          child: Column(
                                            children: [
                                              for (final app in viewModel
                                                  .availableTerminals)
                                                RadioListTile<String>(
                                                  title: Text(app.name,
                                                      style: TextStyle(
                                                          color: colors
                                                              .textPrimary)),
                                                  value: app.id,
                                                  activeColor: colors.accent,
                                                ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 16),
                                      Text('Layout storage',
                                          style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(
                                        'JSON lives in each folder. The database is stored next to your settings and still works when a folder is not writable.',
                                        style: TextStyle(
                                            color: colors.textDim,
                                            fontSize: 11),
                                      ),
                                      const SizedBox(height: 8),
                                      AbsorbPointer(
                                        absorbing: switching,
                                        child: RadioGroup<MetadataBackend>(
                                          groupValue: viewModel.metadataBackend,
                                          onChanged: (value) async {
                                            if (switching || value == null)
                                              return;
                                            final confirmed =
                                                await _confirmMetadataBackendSwitch(
                                              context,
                                              from: viewModel.metadataBackend,
                                              to: value,
                                            );
                                            if (confirmed != true) return;
                                            await viewModel
                                                .setMetadataBackend(value);
                                          },
                                          child: Column(
                                            children: [
                                              RadioListTile<MetadataBackend>(
                                                title: Text(
                                                    'JSON in each folder',
                                                    style: TextStyle(
                                                        color: colors
                                                            .textPrimary)),
                                                subtitle: Text('file-tile.json',
                                                    style: TextStyle(
                                                        color: colors.textDim,
                                                        fontSize: 12)),
                                                value: MetadataBackend.json,
                                                activeColor: colors.accent,
                                              ),
                                              RadioListTile<MetadataBackend>(
                                                title: Text('Local database',
                                                    style: TextStyle(
                                                        color: colors
                                                            .textPrimary)),
                                                subtitle: Text(
                                                    'file-tile-layout.sqlite',
                                                    style: TextStyle(
                                                        color: colors.textDim,
                                                        fontSize: 12)),
                                                value: MetadataBackend.sqlite,
                                                activeColor: colors.accent,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (switching) ...[
                                        const SizedBox(height: 8),
                                        const LinearProgressIndicator(
                                            minHeight: 2),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Switching layout storage…',
                                          style: TextStyle(
                                              color: colors.textDim,
                                              fontSize: 12),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      Text('Controls',
                                          style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Click a key binding to rebind. Pointer chords swap if already used.',
                                        style: TextStyle(
                                            color: colors.textDim,
                                            fontSize: 11),
                                      ),
                                      const SizedBox(height: 8),
                                      for (final action in const [
                                        ControlAction.selectSingle,
                                        ControlAction.toggleSelect,
                                        ControlAction.rangeSelect,
                                        ControlAction.selectionBox,
                                        ControlAction.delete,
                                        ControlAction.copy,
                                        ControlAction.cut,
                                        ControlAction.paste,
                                        ControlAction.undo,
                                        ControlAction.redo,
                                        ControlAction.zoom,
                                        ControlAction.panVertical,
                                        ControlAction.panHorizontal,
                                      ])
                                        _buildBindingRow(
                                          colors,
                                          viewModel,
                                          action,
                                          capturingAction,
                                          (next) => setState(() {
                                            capturingAction = next;
                                          }),
                                        ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () {
                                            viewModel.resetBindings();
                                            setState(
                                                () => capturingAction = null);
                                          },
                                          child: const Text('Reset bindings'),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildControlRow(colors, 'Right Click',
                                          'Open context menu'),
                                      _buildControlRow(
                                          colors, 'Click + Drag', 'Pan canvas'),
                                      _buildControlRow(colors,
                                          'Double-Click Folder', 'Open folder'),
                                      _buildControlRow(
                                          colors,
                                          'Double-Click File',
                                          'Open with system default'),
                                      const SizedBox(height: 16),
                                      // Scroll Settings
                                      Text('Scroll Settings',
                                          style: TextStyle(
                                              color: colors.textSecondary,
                                              fontSize: 12)),
                                      const SizedBox(height: 12),
                                      SwitchListTile(
                                        title: Text('Invert Vertical Scroll',
                                            style: TextStyle(
                                                color: colors.textPrimary)),
                                        value: viewModel.invertVerticalScroll,
                                        onChanged: (value) {
                                          viewModel.invertVerticalScroll =
                                              value;
                                          setState(() {});
                                        },
                                        activeThumbColor: colors.accent,
                                      ),
                                      SwitchListTile(
                                        title: Text('Invert Horizontal Scroll',
                                            style: TextStyle(
                                                color: colors.textPrimary)),
                                        value: viewModel.invertHorizontalScroll,
                                        onChanged: (value) {
                                          viewModel.invertHorizontalScroll =
                                              value;
                                          setState(() {});
                                        },
                                        activeThumbColor: colors.accent,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: switching
                                        ? null
                                        : () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBindingRow(
    FileTileColors colors,
    DesktopViewModel viewModel,
    ControlAction action,
    ControlAction? capturingAction,
    void Function(ControlAction?) setCapturing,
  ) {
    final binding = viewModel.bindings[action];
    final chords = viewModel.bindings.chordsFor(action);
    final Widget control;
    if (chords.isNotEmpty) {
      control = DropdownButton<PointerChord>(
        value: binding.pointer != null && chords.contains(binding.pointer)
            ? binding.pointer
            : chords.first,
        dropdownColor: colors.surface,
        underline: const SizedBox.shrink(),
        style: TextStyle(color: colors.textPrimary, fontSize: 13),
        items: [
          for (final chord in chords)
            DropdownMenuItem(
              value: chord,
              child: Text(chord.label),
            ),
        ],
        onChanged: (chord) {
          if (chord == null) return;
          viewModel.rebindControl(action, ControlBinding.pointer(chord));
          setCapturing(null);
        },
      );
    } else if (capturingAction == action) {
      control = Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            setCapturing(null);
            return KeyEventResult.handled;
          }
          final chord = KeyChord.fromKeyEvent(event);
          if (chord.isModifierOnly) return KeyEventResult.ignored;
          viewModel.rebindControl(action, ControlBinding.key(chord));
          setCapturing(null);
          return KeyEventResult.handled;
        },
        child: TextButton(
          onPressed: () => setCapturing(null),
          child: Text('Press a key…',
              style: TextStyle(color: colors.accent, fontSize: 13)),
        ),
      );
    } else {
      control = TextButton(
        onPressed: () => setCapturing(action),
        child: Text(binding.label,
            style: TextStyle(color: colors.textPrimary, fontSize: 13)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              viewModel.bindings.labelOf(action),
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
          control,
        ],
      ),
    );
  }

  Widget _buildControlRow(
      FileTileColors colors, String control, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            control,
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          Text(
            description,
            style: TextStyle(color: colors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBreadcrumbs(DesktopViewModel viewModel) {
    final path = viewModel.currentDirectory;
    final parts = p.split(path);
    final List<Widget> widgets = [];
    final livePaths = <String>{};

    String currentPath = '';
    if (path.startsWith('/')) {
      currentPath = '/';
      livePaths.add('/');
      final key = _breadcrumbKeys.putIfAbsent('/', GlobalKey.new);
      widgets.add(BreadcrumbSegment(
        key: key,
        label: 'Root',
        onTap: () => viewModel.loadDirectory('/'),
        isDragTarget: _dragTargetBreadcrumbPath == '/',
      ));
    }

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part == '/' || part == '\\' || part.isEmpty) continue;

      currentPath = p.join(currentPath, part);
      final thisPath = currentPath;
      livePaths.add(thisPath);
      final key = _breadcrumbKeys.putIfAbsent(thisPath, GlobalKey.new);
      widgets.add(BreadcrumbSegment(
        key: key,
        label: part,
        onTap: () => viewModel.loadDirectory(thisPath),
        isLast: i == parts.length - 1,
        isDragTarget: _dragTargetBreadcrumbPath == thisPath,
      ));
    }

    _breadcrumbKeys
        .removeWhere((segmentPath, _) => !livePaths.contains(segmentPath));
    return widgets;
  }

  /// Hit-test cursor position against breadcrumb widgets.
  /// Returns the path of the breadcrumb if cursor is over one, or null.
  String? _hitTestBreadcrumb(Offset globalPos) {
    for (final entry in _breadcrumbKeys.entries) {
      final path = entry.key;
      final key = entry.value;
      final context = key.currentContext;
      if (context == null) continue;

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) continue;

      // Get the global position and size of the breadcrumb
      final globalOffset = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final rect = Rect.fromLTWH(
          globalOffset.dx, globalOffset.dy, size.width, size.height);

      if (rect.contains(globalPos)) {
        return path;
      }
    }

    return null;
  }

  Future<void> _showNameConflictDialog(
    BuildContext context, {
    required Set<String> names,
    required String targetPath,
    required List<String> conflictingNames,
    required Future<void> Function() onSkip,
  }) async {
    final nonConflicting =
        names.where((n) => !conflictingNames.contains(n)).toList();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name Conflict'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${conflictingNames.length} item${conflictingNames.length > 1 ? "s" : ""} already exist${conflictingNames.length > 1 ? "" : "s"} in the destination:'),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children:
                      conflictingNames.map((name) => Text('• $name')).toList(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (nonConflicting.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onSkip();
              },
              child: const Text('Skip Conflicts'),
            ),
        ],
      ),
    );
  }
}

class _OsCanvasDropAim {
  final String? folderPath;
  final String? folderName;
  final Offset? folderPosition;
  final Offset? cell;
  final Map<String, Offset>? placements;
  final String? anchorName;

  const _OsCanvasDropAim.folder({
    required this.folderPath,
    required this.folderName,
    required this.folderPosition,
  })  : cell = null,
        placements = null,
        anchorName = null;

  const _OsCanvasDropAim.cell(this.cell)
      : folderPath = null,
        folderName = null,
        folderPosition = null,
        placements = null,
        anchorName = null;

  const _OsCanvasDropAim.reposition({
    required this.cell,
    required this.placements,
    required this.anchorName,
  })  : folderPath = null,
        folderName = null,
        folderPosition = null;
}

enum _BorderSide { top, right, bottom, left }

class _SwitchingLayoutStorageOverlay extends StatelessWidget {
  const _SwitchingLayoutStorageOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
              Text(
                'Switching layout storage…',
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutIssueBanner extends StatelessWidget {
  final DirectoryLayoutIssue issue;

  const _LayoutIssueBanner({required this.issue});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                issue.message,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopNodeWidget extends StatelessWidget {
  final DesktopNode node;
  final double scale;
  final double gridSize;
  final Color directoryColor;
  final Color fileColor;
  final bool isSelected;
  // Deferred: directory search.
  // final bool isSearchMatch;
  final Set<_BorderSide> visibleBorders;
  final bool isDragTarget;
  final IconData icon;
  final ui.Image? thumbnail;

  const _DesktopNodeWidget({
    required this.node,
    required this.scale,
    required this.gridSize,
    required this.directoryColor,
    required this.fileColor,
    required this.icon,
    this.thumbnail,
    this.isSelected = false,
    // Deferred: directory search.
    // this.isSearchMatch = false,
    this.visibleBorders = const {
      _BorderSide.top,
      _BorderSide.right,
      _BorderSide.bottom,
      _BorderSide.left
    },
    this.isDragTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    final size = gridSize * scale;
    final effectiveColor =
        node.color ?? (node.isDirectory ? directoryColor : fileColor);

    final borderColor = isSelected
        ? effectiveColor.withValues(alpha: 0.8)
        : colors.nodeBorderDefault;
    final borderWidth = isSelected ? 2.0 : 0.5;
    // Deferred: directory search highlight.
    // final borderColor = isSelected || isSearchMatch
    //     ? (isSearchMatch && !isSelected
    //         ? colors.accent.withValues(alpha: 0.9)
    //         : effectiveColor.withValues(alpha: 0.8))
    //     : colors.nodeBorderDefault;
    // final borderWidth = isSelected || isSearchMatch ? 2.0 : 0.5;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDragTarget
            ? effectiveColor.withValues(alpha: 0.15)
            : isSelected
                ? effectiveColor.withValues(alpha: 0.15)
                : colors.nodeBackgroundDefault,
        border: isDragTarget
            ? Border.all(color: Colors.transparent)
            : Border(
                top: visibleBorders.contains(_BorderSide.top)
                    ? BorderSide(color: borderColor, width: borderWidth)
                    : BorderSide.none,
                right: visibleBorders.contains(_BorderSide.right)
                    ? BorderSide(color: borderColor, width: borderWidth)
                    : BorderSide.none,
                bottom: visibleBorders.contains(_BorderSide.bottom)
                    ? BorderSide(color: borderColor, width: borderWidth)
                    : BorderSide.none,
                left: visibleBorders.contains(_BorderSide.left)
                    ? BorderSide(color: borderColor, width: borderWidth)
                    : BorderSide.none,
              ),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (thumbnail != null)
                  SizedBox(
                    width: size * 0.45,
                    height: size * 0.45,
                    child: RepaintBoundary(
                      child: RawImage(
                        image: thumbnail,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  )
                else
                  Icon(
                    icon,
                    color: effectiveColor,
                    size: size * 0.45,
                  ),
                SizedBox(height: size * 0.05),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    node.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.nodeLabelText,
                      fontSize: (size * 0.16).clamp(6.0, 16.0),
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (node.isSymlink)
            Positioned(
              top: size * 0.02,
              right: size * 0.02,
              child: Container(
                width: size * 0.22,
                height: size * 0.22,
                decoration: BoxDecoration(
                  color: colors.symlinkBadgeBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.link,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: size * 0.13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  final Offset offset;
  final double scale;
  final Color lineColor;
  final Color originLineColor;

  GridPainter({
    required this.offset,
    required this.scale,
    required this.lineColor,
    required this.originLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridSize = GridConfig.renderGridSize * scale;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    final originPaint = Paint()
      ..color = originLineColor
      ..strokeWidth = 1.5;

    double startX = offset.dx % gridSize;
    for (double x = startX; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    double startY = offset.dy % gridSize;
    for (double y = startY; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    if (offset.dx >= 0 && offset.dx <= size.width) {
      canvas.drawLine(
        Offset(offset.dx, 0),
        Offset(offset.dx, size.height),
        originPaint,
      );
    }
    if (offset.dy >= 0 && offset.dy <= size.height) {
      canvas.drawLine(
        Offset(0, offset.dy),
        Offset(size.width, offset.dy),
        originPaint,
      );
    }

    if (offset.dx >= 0 &&
        offset.dx <= size.width &&
        offset.dy >= 0 &&
        offset.dy <= size.height) {
      canvas.drawCircle(offset, 3.0, originPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.originLineColor != originLineColor;
  }
}
