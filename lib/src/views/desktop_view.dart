import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../viewmodels/desktop_viewmodel.dart';
import '../widgets/breadcrumb_segment.dart';
import '../widgets/cascading_menu.dart';

class DesktopView extends StatefulWidget {
  const DesktopView({super.key});

  @override
  State<DesktopView> createState() => _DesktopViewState();
}

class _DesktopViewState extends State<DesktopView> {
  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<DesktopViewModel>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        toolbarHeight: 40,
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Listener(
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
                    onTap: () {
                      viewModel.deselectNode();
                    },
                    onPanUpdate: (details) {
                      viewModel.offset = viewModel.offset + details.delta;
                    },
                    onSecondaryTapDown: (details) {
                      _showBackgroundContextMenu(context, details.globalPosition, viewModel);
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
                ...viewModel.nodes.map((node) {
                  final screenPos = viewModel.offset + (node.position * viewModel.scale);
                  final isSelected = viewModel.selectedNodeName == node.name;
                  return Positioned(
                    left: screenPos.dx,
                    top: screenPos.dy,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        viewModel.updateNodePosition(node.name, details.delta / viewModel.scale);
                      },
                      onPanEnd: (_) {
                        viewModel.snapNodeToGrid(node.name);
                      },
                      onTap: () {
                        if (isSelected) {
                          viewModel.deselectNode();
                        } else {
                          viewModel.selectNode(node.name);
                        }
                      },
                      onSecondaryTapDown: (details) {
                        if (!isSelected) {
                          viewModel.selectNode(node.name);
                        }
                        _showNodeContextMenu(context, details.globalPosition, node, viewModel);
                      },
                      onDoubleTap: node.isDirectory
                        ? () => viewModel.loadDirectory(p.join(viewModel.currentDirectory, node.name))
                        : null,
                      child: _DesktopNodeWidget(
                        node: node,
                        scale: viewModel.scale,
                        gridSize: DesktopViewModel.gridSize,
                        directoryColor: viewModel.directoryColor,
                        fileColor: viewModel.fileColor,
                        isSelected: isSelected,
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
    );
  }

  void _showBackgroundContextMenu(BuildContext context, Offset position, DesktopViewModel viewModel) {
    CascadingMenu.show(
      context,
      position: position,
      items: [
        CascadingMenuItem(
          label: 'New Folder',
          icon: Icons.create_new_folder,
          onTap: () {
            final gridPos = viewModel.pixelPosToGridPos(position - viewModel.offset);
            _promptCreate(context, viewModel, isDirectory: true, gridPosition: gridPos);
          },
        ),
        CascadingMenuItem(
          label: 'New File',
          icon: Icons.note_add,
          onTap: () {
            final gridPos = viewModel.pixelPosToGridPos(position - viewModel.offset);
            _promptCreate(context, viewModel, isDirectory: false, gridPosition: gridPos);
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

  void _showNodeContextMenu(BuildContext context, Offset position, DesktopNode node, DesktopViewModel viewModel) {
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
        onTap: () => _confirmDelete(context, viewModel, node, () => Navigator.pop(context)),
      ),
    ];

    CascadingMenu.show(
      context,
      position: position,
      items: items,
    );
  }

  Future<void> _promptCreate(BuildContext context, DesktopViewModel viewModel, {required bool isDirectory, Offset? gridPosition}) async {
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
                viewModel.createDirectory(value, gridPosition: gridPosition);
              } else {
                viewModel.createFile(value, gridPosition: gridPosition);
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
                  viewModel.createDirectory(controller.text, gridPosition: gridPosition);
                } else {
                  viewModel.createFile(controller.text, gridPosition: gridPosition);
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

  Future<void> _confirmDelete(BuildContext context, DesktopViewModel viewModel, DesktopNode node, VoidCallback onConfirm) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${node.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await viewModel.deleteNode(node.name);
              if (context.mounted) {
                Navigator.pop(context);
              }
              onConfirm();
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

    String currentPath = '';
    if (path.startsWith('/')) {
      currentPath = '/';
      widgets.add(BreadcrumbSegment(
        label: 'Root',
        onTap: () => viewModel.loadDirectory('/'),
      ));
    }

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part == '/' || part == '\\' || part.isEmpty) continue;

      currentPath = p.join(currentPath, part);
      final thisPath = currentPath;
      widgets.add(BreadcrumbSegment(
        label: part,
        onTap: () => viewModel.loadDirectory(thisPath),
        isLast: i == parts.length - 1,
      ));
    }

    return widgets;
  }
}

class _DesktopNodeWidget extends StatelessWidget {
  final DesktopNode node;
  final double scale;
  final double gridSize;
  final Color directoryColor;
  final Color fileColor;
  final bool isSelected;

  const _DesktopNodeWidget({
    required this.node,
    required this.scale,
    required this.gridSize,
    required this.directoryColor,
    required this.fileColor,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = gridSize * scale;
    final effectiveColor = node.color ?? (node.isDirectory ? directoryColor : fileColor);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSelected
          ? effectiveColor.withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.02),
        border: Border.all(
          color: isSelected
            ? effectiveColor.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.05),
          width: isSelected ? 2.0 : 0.5,
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
  static const double baseGridSize = 40.0;

  GridPainter({required this.offset, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final gridSize = baseGridSize * scale;

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
