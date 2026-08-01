import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../controllers/click_handler.dart';
import '../models/click_event.dart';
import '../viewmodels/desktop_viewmodel.dart';
import '../widgets/breadcrumb_segment.dart';
import '../widgets/cascading_menu.dart';
import '../utils/coordinate_space.dart';

export '../viewmodels/desktop_viewmodel.dart' show DesktopSelectAction;

class DesktopView extends StatefulWidget {
  const DesktopView({super.key});

  @override
  State<DesktopView> createState() => _DesktopViewState();
}

class _DesktopViewState extends State<DesktopView> {
  late FocusNode _focusNode;
  late ClickHandler _clickHandler;
  Offset? _currentDragCursorPos;
  String? _dragTargetNodeName; // Name of the directory being hovered as a drop target
  String? _dragTargetBreadcrumbPath; // Path of the breadcrumb being hovered as a drop target
  final Map<String, GlobalKey> _breadcrumbKeys = {}; // Map of path -> GlobalKey for hit-testing

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      final viewModel = context.read<DesktopViewModel>();
      _clickHandler = ClickHandler(selectionController: viewModel.selectionController);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.delete) {
      final viewModel = context.read<DesktopViewModel>();
      if (viewModel.selectedNodeNames.isNotEmpty) {
        _confirmDeleteSelected(context, viewModel);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Set<_BorderSide> _getVisibleBorders(DesktopNode node, DesktopViewModel viewModel) {
    if (!viewModel.isNodeSelected(node.name)) {
      return {_BorderSide.top, _BorderSide.right, _BorderSide.bottom, _BorderSide.left};
    }

    final visibleBorders = <_BorderSide>{_BorderSide.top, _BorderSide.right, _BorderSide.bottom, _BorderSide.left};
    final nodeColor = node.color ?? (node.isDirectory ? viewModel.directoryColor : viewModel.fileColor);
    final gridSize = GridConfig.gridCellSize;

    // Check each neighbor direction and suppress borders if adjacent selected node has same color
    for (final neighbor in viewModel.nodes) {
      if (neighbor.name == node.name) continue;

      final isNeighborSelected = viewModel.isNodeSelected(neighbor.name);
      if (!isNeighborSelected) continue;

      final neighborColor = neighbor.color ?? (neighbor.isDirectory ? viewModel.directoryColor : viewModel.fileColor);
      final isSameColor = nodeColor == neighborColor;
      if (!isSameColor) continue;

      final dx = neighbor.position.dx - node.position.dx;
      final dy = neighbor.position.dy - node.position.dy;
      const tolerance = 1.0;

      // Top neighbor (dy = -gridSize, dx = 0)
      if ((dy + gridSize).abs() < tolerance && dx.abs() < tolerance) {
        visibleBorders.remove(_BorderSide.top);
      }
      // Right neighbor (dx = gridSize, dy = 0)
      else if ((dx - gridSize).abs() < tolerance && dy.abs() < tolerance) {
        visibleBorders.remove(_BorderSide.right);
      }
      // Bottom neighbor (dy = gridSize, dx = 0)
      else if ((dy - gridSize).abs() < tolerance && dx.abs() < tolerance) {
        visibleBorders.remove(_BorderSide.bottom);
      }
      // Left neighbor (dx = -gridSize, dy = 0)
      else if ((dx + gridSize).abs() < tolerance && dy.abs() < tolerance) {
        visibleBorders.remove(_BorderSide.left);
      }
    }

    return visibleBorders;
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<DesktopViewModel>();

    final error = viewModel.lastError;
    if (error != null) {
      viewModel.clearError();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        toolbarHeight: AppConfig.appBarHeight,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 18),
              onPressed: viewModel.canGoBack ? viewModel.back : null,
              tooltip: 'Back',
              color: viewModel.canGoBack ? Colors.white : Colors.grey,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 18),
              onPressed: viewModel.canGoForward ? viewModel.forward : null,
              tooltip: 'Forward',
              color: viewModel.canGoForward ? Colors.white : Colors.grey,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: viewModel.navigateUp,
              tooltip: 'Go Up',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _buildBreadcrumbs(viewModel),
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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsModal(context, viewModel),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Listener(
            onPointerDown: (event) {
              // Adjust click position from window to canvas coordinates
              final canvasPosition = event.position - Offset(0, AppConfig.appBarHeight);

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
                final hitNode = nodes.any((n) => n.hitsPoint(canvasPosition, viewModel.coords));
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
                final result = _clickHandler.handleSecondaryPointerDown(
                  screenPosition: canvasPosition,
                  nodes: nodes,
                  coords: viewModel.coords,
                );

                switch (result) {
                  case NodeClickResult(nodeId: final nodeId):
                    // Click handler already selected the node
                    _showNodeContextMenu(context, event.position, viewModel);
                  case BackgroundClickResult():
                    _showBackgroundContextMenu(context, event.position, result.logicalPosition, viewModel);
                }
              }
            },
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
                final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

                if (isCtrlPressed) {
                  // Ctrl + scroll = zoom
                  double zoomFactor = 1.1;
                  double newScale = viewModel.scale;
                  if (pointerSignal.scrollDelta.dy > 0) {
                    newScale /= zoomFactor;
                  } else {
                    newScale *= zoomFactor;
                  }
                  viewModel.scale = newScale.clamp(0.1, 10.0);
                } else if (isShiftPressed) {
                  // Shift + scroll = horizontal pan
                  final delta = viewModel.invertHorizontalScroll
                    ? -pointerSignal.scrollDelta.dy
                    : pointerSignal.scrollDelta.dy;
                  viewModel.offset = viewModel.offset + Offset(delta, 0);
                } else {
                  // Default = vertical pan
                  final delta = viewModel.invertVerticalScroll
                    ? -pointerSignal.scrollDelta.dy
                    : pointerSignal.scrollDelta.dy;
                  viewModel.offset = viewModel.offset + Offset(0, delta);
                }
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      viewModel.offset = viewModel.offset + details.delta;
                    },
                    child: ClipRect(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: GridPainter(
                          offset: viewModel.offset,
                          scale: viewModel.scale,
                        ),
                      ),
                    ),
                  ),
                ),
                ...viewModel.orderedNodes.map((node) {
                  final screenPos = viewModel.coords.logicalToScreen(node.position);
                  final isSelected = viewModel.isNodeSelected(node.name);
                  final visibleBorders = _getVisibleBorders(node, viewModel);
                  return Positioned(
                    key: ValueKey(node.name),
                    left: screenPos.dx,
                    top: screenPos.dy,
                    child: GestureDetector(
                      // Flutter's gesture arena natively disambiguates tap vs. drag on this
                      // same GestureDetector: onTap fires only if the pointer never moves
                      // beyond the touch slop; onPanUpdate/onPanEnd fire once real movement
                      // is detected. No manual timers needed.
                      onTap: () {
                        final hitTestNodes = viewModel.nodes.map((n) {
                          return HitTestNode(
                            id: n.name,
                            position: n.position,
                            size: GridConfig.gridCellSize,
                          );
                        }).toList();
                        _clickHandler.handleNodeTap(nodeId: node.name, nodes: hitTestNodes);
                      },
                      onPanDown: (_) {
                        // Determine which nodes are being dragged
                        final nodesToDrag = viewModel.isNodeSelected(node.name) && viewModel.selectedNodeNames.length > 1
                          ? viewModel.selectedNodeNames
                          : {node.name};
                        viewModel.startDrag(nodesToDrag);
                        _currentDragCursorPos = null;
                      },
                      onPanCancel: () {
                        // Pan lost the gesture arena to the tap recognizer (or was otherwise
                        // interrupted) - clear the drag state we speculatively captured.
                        viewModel.cancelDrag();
                        _currentDragCursorPos = null;
                      },
                      onPanUpdate: (details) {
                        _currentDragCursorPos = details.globalPosition;
                        final delta = viewModel.coords.screenDeltaToLogicalDelta(details.delta);

                        // Determine which nodes are being dragged
                        final nodesDragging = viewModel.isNodeSelected(node.name) && viewModel.selectedNodeNames.length > 1
                          ? viewModel.selectedNodeNames
                          : {node.name};

                        // If this node is selected and there are multiple selections, drag all
                        if (viewModel.isNodeSelected(node.name) && viewModel.selectedNodeNames.length > 1) {
                          for (final selectedNodeId in viewModel.selectedNodeNames) {
                            viewModel.updateNodePosition(selectedNodeId, delta);
                          }
                        } else {
                          // Single node drag
                          viewModel.updateNodePosition(node.name, delta);
                        }

                        // Update which directory or breadcrumb is being hovered as a drop target
                        String? targetNodeName;
                        String? targetBreadcrumbPath;

                        // Check breadcrumbs first (they're in the AppBar, higher priority)
                        final breadcrumbPath = _hitTestBreadcrumb(details.globalPosition);
                        if (breadcrumbPath != null && !nodesDragging.contains(p.basename(breadcrumbPath))) {
                          targetBreadcrumbPath = breadcrumbPath;
                        } else {
                          // Check directory widgets in the grid
                          final targetDir = _hitTestDirectoryWidget(
                            details.globalPosition,
                            viewModel,
                            excludeNodeNames: nodesDragging,
                          );
                          if (targetDir != null) {
                            for (final n in viewModel.nodes) {
                              if (p.join(viewModel.currentDirectory, n.name) == targetDir) {
                                targetNodeName = n.name;
                                break;
                              }
                            }
                          }
                        }

                        setState(() {
                          _dragTargetNodeName = targetNodeName;
                          _dragTargetBreadcrumbPath = targetBreadcrumbPath;
                        });
                      },
                      onPanEnd: (details) async {
                        // Determine which nodes were being dragged
                        final nodesDragged = viewModel.isNodeSelected(node.name) && viewModel.selectedNodeNames.length > 1
                          ? viewModel.selectedNodeNames
                          : {node.name};

                        // Check breadcrumbs first (higher priority than grid)
                        final breadcrumbPath = _hitTestBreadcrumb(details.globalPosition);
                        if (breadcrumbPath != null && !nodesDragged.contains(p.basename(breadcrumbPath))) {
                          await viewModel.moveNodesToDirectory(nodesDragged, breadcrumbPath);
                          setState(() {
                            _dragTargetNodeName = null;
                            _dragTargetBreadcrumbPath = null;
                          });
                          _currentDragCursorPos = null;
                          return;
                        }

                        // Check directory widgets in the grid
                        final targetDirectory = _hitTestDirectoryWidget(
                          details.globalPosition,
                          viewModel,
                          excludeNodeNames: nodesDragged,
                        );
                        if (targetDirectory != null) {
                          await viewModel.moveNodesToDirectory(nodesDragged, targetDirectory);
                          setState(() {
                            _dragTargetNodeName = null;
                            _dragTargetBreadcrumbPath = null;
                          });
                          _currentDragCursorPos = null;
                          return;
                        }

                        // No drop target found - snap to grid with collision detection
                        await viewModel.completeOrRevertDrag(nodesDragged);
                        setState(() {
                          _dragTargetNodeName = null;
                          _dragTargetBreadcrumbPath = null;
                        });
                        _currentDragCursorPos = null;
                      },
                      onDoubleTap: node.isDirectory
                        ? () => viewModel.loadDirectory(p.join(viewModel.currentDirectory, node.name))
                        : null,
                      child: _DesktopNodeWidget(
                        node: node,
                        scale: viewModel.scale,
                        gridSize: GridConfig.gridCellSize,
                        directoryColor: viewModel.directoryColor,
                        fileColor: viewModel.fileColor,
                        isSelected: isSelected,
                        visibleBorders: visibleBorders,
                        isDragTarget: _dragTargetNodeName == node.name,
                      ),
                    ),
                  );
                }),
                if (viewModel.isLoading)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            );
          },
        ),
      ),
    );
  }

  void _showBackgroundContextMenu(BuildContext context, Offset globalPosition, Offset logicalPosition, DesktopViewModel viewModel) {
    CascadingMenu.show(
      context,
      position: globalPosition,
      onBarrierLeftTapped: (globalPos) {
        final canvasPosition = globalPos - Offset(0, AppConfig.appBarHeight);
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
        final canvasPosition = globalPos - Offset(0, AppConfig.appBarHeight);
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
            _showBackgroundContextMenu(context, globalPos, result.logicalPosition, viewModel);
        }
      },
      items: [
        CascadingMenuItem(
          label: 'New Folder',
          icon: Icons.create_new_folder,
          onTap: () {
            final snappedPos = viewModel.coords.snapToCellCorner(logicalPosition);
            final (gridX, gridY) = viewModel.coords.logicalPosToGridIndices(snappedPos);
            debugPrint('[CREATE FOLDER] logical: (${logicalPosition.dx.toStringAsFixed(1)}, ${logicalPosition.dy.toStringAsFixed(1)}) | snapped: (${snappedPos.dx.toStringAsFixed(1)}, ${snappedPos.dy.toStringAsFixed(1)}) | grid: ($gridX, $gridY)');
            _promptCreate(context, viewModel, isDirectory: true, gridPosition: snappedPos, originalLogicalPos: logicalPosition);
          },
        ),
        CascadingMenuItem(
          label: 'New File',
          icon: Icons.note_add,
          onTap: () {
            final snappedPos = viewModel.coords.snapToCellCorner(logicalPosition);
            _promptCreate(context, viewModel, isDirectory: false, gridPosition: snappedPos, originalLogicalPos: logicalPosition);
          },
        ),
        CascadingMenuItem.divider(),
        CascadingMenuItem(
          label: 'Refresh',
          icon: Icons.refresh,
          onTap: () => viewModel.refresh(),
        ),
      ],
    );
  }

  void _showNodeContextMenu(BuildContext context, Offset position, DesktopViewModel viewModel) {
    final selectedNodes = viewModel.selectedNodeNames.map((name) => viewModel.nodes.firstWhere((n) => n.name == name)).toList();
    if (selectedNodes.isEmpty) return;
    final node = selectedNodes.first;
    final extension = p.extension(node.name).toLowerCase();
    final isBash = extension == '.sh';
    final isPython = extension == '.py';
    final isNode = extension == '.js' || extension == '.mjs' || extension == '.cjs' || extension == '.ts';
    final available = viewModel.appRegistry.where((app) => viewModel.availableApps[app['cmd']] == true).toList();

    final items = <CascadingMenuItem>[
      CascadingMenuItem(
        label: 'Open',
        icon: node.isDirectory ? Icons.folder_open : Icons.open_in_new,
        onTap: node.isDirectory
          ? () => viewModel.loadDirectory(p.join(viewModel.currentDirectory, node.name))
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
      CascadingMenuItem(
        label: 'Rename',
        icon: Icons.edit,
        onTap: () => _promptRename(context, viewModel, node, () => Navigator.pop(context)),
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
                onTap: () => _runScript(context, viewModel, 'python3', node.name),
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
            onTap: () => viewModel.updateNodeColor(node.name, Colors.greenAccent),
          ),
          CascadingMenuItem(
            label: 'Blue',
            onTap: () => viewModel.updateNodeColor(node.name, Colors.blueAccent),
          ),
          CascadingMenuItem(
            label: 'Orange',
            onTap: () => viewModel.updateNodeColor(node.name, Colors.orangeAccent),
          ),
          CascadingMenuItem(
            label: 'Purple',
            onTap: () => viewModel.updateNodeColor(node.name, Colors.purpleAccent),
          ),
          CascadingMenuItem(
            label: 'Pink',
            onTap: () => viewModel.updateNodeColor(node.name, Colors.pinkAccent),
          ),
          CascadingMenuItem(
            label: 'Teal',
            onTap: () => viewModel.updateNodeColor(node.name, Colors.tealAccent),
          ),
        ],
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
        final canvasPosition = globalPos - Offset(0, AppConfig.appBarHeight);
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
        final canvasPosition = globalPos - Offset(0, AppConfig.appBarHeight);
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
            _showBackgroundContextMenu(context, globalPos, result.logicalPosition, viewModel);
        }
      },
      items: items,
    );
  }

  Future<void> _promptCreate(BuildContext context, DesktopViewModel viewModel, {required bool isDirectory, Offset? gridPosition, Offset? originalLogicalPos}) async {
    final controller = TextEditingController();
    final type = isDirectory ? 'Folder' : 'File';

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('New $type', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: const TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              if (isDirectory) {
                viewModel.createDirectory(value, gridPosition: gridPosition, originalLogicalPos: originalLogicalPos);
              } else {
                viewModel.createFile(value, gridPosition: gridPosition, originalLogicalPos: originalLogicalPos);
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
                  viewModel.createDirectory(controller.text, gridPosition: gridPosition, originalLogicalPos: originalLogicalPos);
                } else {
                  viewModel.createFile(controller.text, gridPosition: gridPosition, originalLogicalPos: originalLogicalPos);
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

  Future<void> _promptRename(BuildContext context, DesktopViewModel viewModel, DesktopNode node, VoidCallback onConfirm) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;
    final controller = TextEditingController(text: node.name);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Rename', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter new name',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'code': return Icons.code;
      case 'terminal': return Icons.terminal;
      case 'edit': return Icons.edit;
      case 'folder_open': return Icons.folder_open;
      default: return Icons.apps;
    }
  }

  Future<void> _runScript(BuildContext context, DesktopViewModel viewModel, String tool, String fileName) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Running $fileName with $tool...'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blueAccent,
      ),
    );

    final result = await viewModel.runScript(tool, fileName);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Result: $fileName ($tool)', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(
            result,
            style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
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

  Future<void> _confirmDeleteSelected(BuildContext context, DesktopViewModel viewModel) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;

    final selectedNames = viewModel.selectedNodeNames.toList()..sort();
    final isMultiple = selectedNames.length > 1;
    final deleteMessage = isMultiple
        ? 'Are you sure you want to delete ${selectedNames.length} items?\n\n${selectedNames.join('\n')}'
        : 'Are you sure you want to delete "${selectedNames.first}"?';

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(deleteMessage, style: const TextStyle(color: Colors.white70)),
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
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal(BuildContext context, DesktopViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Settings', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Scroll Settings', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Invert Vertical Scroll', style: TextStyle(color: Colors.white)),
                  value: viewModel.invertVerticalScroll,
                  onChanged: (value) {
                    viewModel.invertVerticalScroll = value;
                    setState(() {});
                  },
                  activeThumbColor: Colors.blueAccent,
                ),
                SwitchListTile(
                  title: const Text('Invert Horizontal Scroll', style: TextStyle(color: Colors.white)),
                  value: viewModel.invertHorizontalScroll,
                  onChanged: (value) {
                    viewModel.invertHorizontalScroll = value;
                    setState(() {});
                  },
                  activeThumbColor: Colors.blueAccent,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBreadcrumbs(DesktopViewModel viewModel) {
    final path = viewModel.currentDirectory;
    final parts = p.split(path);
    final List<Widget> widgets = [];
    _breadcrumbKeys.clear();

    String currentPath = '';
    if (path.startsWith('/')) {
      currentPath = '/';
      final key = GlobalKey();
      _breadcrumbKeys['/'] = key;
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
      final key = GlobalKey();
      _breadcrumbKeys[thisPath] = key;
      widgets.add(BreadcrumbSegment(
        key: key,
        label: part,
        onTap: () => viewModel.loadDirectory(thisPath),
        isLast: i == parts.length - 1,
        isDragTarget: _dragTargetBreadcrumbPath == thisPath,
      ));
    }

    return widgets;
  }

  /// Hit-test cursor position against directory widgets in the grid.
  /// Returns the path of the directory if cursor is over one, or null.
  /// Excludes directories that are currently being dragged.
  String? _hitTestDirectoryWidget(
    Offset globalPos,
    DesktopViewModel viewModel, {
    Set<String> excludeNodeNames = const {},
  }) {
    // Convert global position to canvas position
    final canvasPos = globalPos - Offset(0, AppConfig.appBarHeight);

    // Test each node to see if cursor is over a directory
    for (final node in viewModel.nodes) {
      if (!node.isDirectory) continue;
      if (excludeNodeNames.contains(node.name)) continue;

      final screenPos = viewModel.coords.logicalToScreen(node.position);
      final scaledSize = GridConfig.gridCellSize * viewModel.scale;
      final rect = Rect.fromLTWH(screenPos.dx, screenPos.dy, scaledSize, scaledSize);

      if (rect.contains(canvasPos)) {
        final targetPath = p.join(viewModel.currentDirectory, node.name);
        return targetPath;
      }
    }

    return null;
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
      final rect = Rect.fromLTWH(globalOffset.dx, globalOffset.dy, size.width, size.height);

      if (rect.contains(globalPos)) {
        return path;
      }
    }

    return null;
  }
}

enum _BorderSide { top, right, bottom, left }

class _DesktopNodeWidget extends StatelessWidget {
  final DesktopNode node;
  final double scale;
  final double gridSize;
  final Color directoryColor;
  final Color fileColor;
  final bool isSelected;
  final Set<_BorderSide> visibleBorders;
  final bool isDragTarget;

  const _DesktopNodeWidget({
    required this.node,
    required this.scale,
    required this.gridSize,
    required this.directoryColor,
    required this.fileColor,
    this.isSelected = false,
    this.visibleBorders = const {_BorderSide.top, _BorderSide.right, _BorderSide.bottom, _BorderSide.left},
    this.isDragTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = gridSize * scale;
    final effectiveColor = node.color ?? (node.isDirectory ? directoryColor : fileColor);

    final borderColor = isSelected
      ? effectiveColor.withValues(alpha: 0.8)
      : Colors.white.withValues(alpha: 0.05);
    final borderWidth = isSelected ? 2.0 : 0.5;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDragTarget
          ? effectiveColor.withValues(alpha: 0.15)
          : isSelected
            ? effectiveColor.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.02),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            node.isDirectory ? Icons.folder : Icons.description,
            color: effectiveColor.withValues(alpha: 0.8),
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
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: (size * 0.16).clamp(6.0, 16.0),
                height: 1.1,
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

  GridPainter({required this.offset, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final gridSize = GridConfig.renderGridSize * scale;

    final paint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1.0;

    final originPaint = Paint()
      ..color = const Color(0xFF444444)
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

    if (offset.dx >= 0 && offset.dx <= size.width && offset.dy >= 0 && offset.dy <= size.height) {
      canvas.drawCircle(offset, 3.0, originPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.offset != offset || oldDelegate.scale != scale;
  }
}
