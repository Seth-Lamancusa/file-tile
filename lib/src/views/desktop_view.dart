import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../viewmodels/desktop_viewmodel.dart';
import '../widgets/breadcrumb_segment.dart';

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
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                double zoomFactor = 1.1;
                double newScale = viewModel.scale;
                if (pointerSignal.scrollDelta.dy > 0) {
                  newScale /= zoomFactor;
                } else {
                  newScale *= zoomFactor;
                }
                viewModel.scale = newScale.clamp(0.1, 10.0);
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
                      onSecondaryTapDown: (details) {
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
    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1E1E1E),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          onTap: () => _promptCreate(context, viewModel, isDirectory: true),
          child: const Row(
            children: [
              Icon(Icons.create_new_folder, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Text('New Folder', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => _promptCreate(context, viewModel, isDirectory: false),
          child: const Row(
            children: [
              Icon(Icons.note_add, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Text('New File', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          onTap: () => viewModel.refresh(),
          child: const Row(
            children: [
              Icon(Icons.refresh, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Text('Refresh', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  void _showNodeContextMenu(BuildContext context, Offset position, DesktopNode node, DesktopViewModel viewModel) {
    final extension = p.extension(node.name).toLowerCase();
    final isBash = extension == '.sh';
    final isPython = extension == '.py';
    final isNode = extension == '.js' || extension == '.mjs' || extension == '.cjs' || extension == '.ts';

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1E1E1E),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          onTap: node.isDirectory
            ? () => viewModel.loadDirectory(p.join(viewModel.currentDirectory, node.name))
            : () => viewModel.openSystemDefault(node.name),
          child: Row(
            children: [
              Icon(node.isDirectory ? Icons.folder_open : Icons.open_in_new, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              const Text('Open', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showOpenWithMenu(context, position, viewModel, node.name);
              }
            });
          },
          child: const Row(
            children: [
              Icon(Icons.apps, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Expanded(child: Text('Open With...', style: TextStyle(color: Colors.white, fontSize: 13))),
              Icon(Icons.chevron_right, color: Colors.white54, size: 16),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => _promptRename(context, viewModel, node),
          child: const Row(
            children: [
              Icon(Icons.edit, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text('Rename', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        if (!node.isDirectory && (isBash || isPython || isNode)) ...[
          const PopupMenuDivider(height: 1),
          if (isBash)
            PopupMenuItem(
              child: const Row(
                children: [
                  Icon(Icons.terminal, color: Colors.white70, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('Bash Script', style: TextStyle(color: Colors.white, fontSize: 13))),
                  Icon(Icons.chevron_right, color: Colors.white54, size: 16),
                ],
              ),
              onTap: () {
                Navigator.pop(context);
                _showScriptRunMenu(context, position, viewModel, 'bash', node.name);
              },
            ),
          if (isPython)
            PopupMenuItem(
              child: const Row(
                children: [
                  Icon(Icons.code, color: Colors.white70, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('Python Script', style: TextStyle(color: Colors.white, fontSize: 13))),
                  Icon(Icons.chevron_right, color: Colors.white54, size: 16),
                ],
              ),
              onTap: () {
                Navigator.pop(context);
                _showScriptRunMenu(context, position, viewModel, 'python3', node.name);
              },
            ),
          if (isNode)
            PopupMenuItem(
              child: const Row(
                children: [
                  Icon(Icons.javascript, color: Colors.white70, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('Node.js Script', style: TextStyle(color: Colors.white, fontSize: 13))),
                  Icon(Icons.chevron_right, color: Colors.white54, size: 16),
                ],
              ),
              onTap: () {
                Navigator.pop(context);
                _showScriptRunMenu(context, position, viewModel, 'node', node.name);
              },
            ),
        ],
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          onTap: () {
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                _showColorPicker(context, position, node, viewModel);
              }
            });
          },
          child: const Row(
            children: [
              Icon(Icons.palette, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Expanded(child: Text('Change Color', style: TextStyle(color: Colors.white, fontSize: 13))),
              Icon(Icons.chevron_right, color: Colors.white54, size: 16),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          onTap: () => _confirmDelete(context, viewModel, node),
          child: const Row(
            children: [
              Icon(Icons.delete, color: Colors.redAccent, size: 20),
              const SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context, Offset position, DesktopNode node, DesktopViewModel viewModel) {
    final colors = [
      null, // Reset to default
      Colors.redAccent,
      Colors.greenAccent,
      Colors.blueAccent,
      Colors.orangeAccent,
      Colors.purpleAccent,
      Colors.pinkAccent,
      Colors.tealAccent,
    ];

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1E1E1E),
      items: colors.map<PopupMenuEntry<dynamic>>((color) => PopupMenuItem(
        onTap: () => viewModel.updateNodeColor(node.name, color),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color ?? (node.isDirectory ? viewModel.directoryColor : viewModel.fileColor),
                shape: BoxShape.circle,
                border: color == null ? Border.all(color: Colors.white54) : null,
              ),
              child: color == null ? const Icon(Icons.close, size: 12, color: Colors.white54) : null,
            ),
            const SizedBox(width: 12),
            Text(
              color == null ? 'Default' : _colorName(color),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      )).toList(),
    );
  }

  String _colorName(Color color) {
    if (color == Colors.redAccent) return 'Red';
    if (color == Colors.greenAccent) return 'Green';
    if (color == Colors.blueAccent) return 'Blue';
    if (color == Colors.orangeAccent) return 'Orange';
    if (color == Colors.purpleAccent) return 'Purple';
    if (color == Colors.pinkAccent) return 'Pink';
    if (color == Colors.tealAccent) return 'Teal';
    return 'Custom';
  }

  Future<void> _promptCreate(BuildContext context, DesktopViewModel viewModel, {required bool isDirectory}) async {
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
                viewModel.createDirectory(value);
              } else {
                viewModel.createFile(value);
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
                  viewModel.createDirectory(controller.text);
                } else {
                  viewModel.createFile(controller.text);
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

  Future<void> _promptRename(BuildContext context, DesktopViewModel viewModel, DesktopNode node) async {
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
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showOpenWithMenu(BuildContext context, Offset position, DesktopViewModel viewModel, String fileName) {
    final available = viewModel.appRegistry.where((app) => viewModel.availableApps[app['cmd']] == true).toList();

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1E1E1E),
      items: [
        PopupMenuItem(
          onTap: () => viewModel.openSystemDefault(fileName),
          child: const Row(
            children: [
              Icon(Icons.settings_suggest, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Text('System Default', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        if (available.isNotEmpty) const PopupMenuDivider(height: 1),
        ...available.map((app) => PopupMenuItem(
          onTap: () => viewModel.openWith(app['cmd']!, fileName),
          child: Row(
            children: [
              Icon(_getIconData(app['icon']!), color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text(app['name']!, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        )),
      ],
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

  void _showScriptRunMenu(BuildContext context, Offset position, DesktopViewModel viewModel, String tool, String fileName) {
    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1E1E1E),
      items: [
        PopupMenuItem(
          onTap: () => _runScript(context, viewModel, tool, fileName),
          child: Row(
            children: [
              const Icon(Icons.output, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text('Capture Output (Dialog)', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => viewModel.runInTerminal(tool, fileName),
          child: Row(
            children: [
              const Icon(Icons.terminal, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text('Run in Terminal (Interactive)', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
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

  Future<void> _confirmDelete(BuildContext context, DesktopViewModel viewModel, DesktopNode node) async {
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
            onPressed: () {
              viewModel.deleteNode(node.name);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
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

  const _DesktopNodeWidget({
    required this.node,
    required this.scale,
    required this.gridSize,
    required this.directoryColor,
    required this.fileColor,
  });

  @override
  Widget build(BuildContext context) {
    final size = gridSize * scale;
    final effectiveColor = node.color ?? (node.isDirectory ? directoryColor : fileColor);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
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
                fontSize: (size * 0.12).clamp(5.0, 12.0),
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
