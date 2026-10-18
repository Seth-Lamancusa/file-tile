import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/coordinate_space.dart';
import '../utils/grid_position.dart';

/// Dashed outline of the cells a drop will occupy, plus one add-file glyph
/// on the cell where the OS drag image lands.
class OsDropTargetOverlay extends StatelessWidget {
  final List<Offset> cells;
  final Offset anchor;
  final CoordinateSpace coords;
  final Color color;

  const OsDropTargetOverlay({
    super.key,
    required this.cells,
    required this.anchor,
    required this.coords,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final anchorScreen = coords.logicalToScreen(anchor);
    final size = coords.renderedGridCellSize;
    final anchorRect = Rect.fromLTWH(
      anchorScreen.dx,
      anchorScreen.dy,
      size,
      size,
    );
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DropRegionOutlinePainter(
                cells: cells,
                coords: coords,
                color: color,
              ),
            ),
          ),
          Positioned.fromRect(
            rect: anchorRect,
            child: Center(
              child: Icon(
                Icons.note_add_outlined,
                color: color,
                size: (anchorRect.shortestSide * 0.4).clamp(16.0, 36.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropRegionOutlinePainter extends CustomPainter {
  final List<Offset> cells;
  final CoordinateSpace coords;
  final Color color;

  _DropRegionOutlinePainter({
    required this.cells,
    required this.coords,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cellSize = coords.renderedGridCellSize;
    for (final cell in cells) {
      final screen = coords.logicalToScreen(cell);
      final rect = Rect.fromLTWH(screen.dx, screen.dy, cellSize, cellSize);
      final sides = outerCellOutlineSides(
        cell,
        cells,
        GridConfig.gridCellSize,
      );
      if (sides.contains(CellOutlineSide.top)) {
        _dash(canvas, rect.topLeft, rect.topRight, paint);
      }
      if (sides.contains(CellOutlineSide.right)) {
        _dash(canvas, rect.topRight, rect.bottomRight, paint);
      }
      if (sides.contains(CellOutlineSide.bottom)) {
        _dash(canvas, rect.bottomLeft, rect.bottomRight, paint);
      }
      if (sides.contains(CellOutlineSide.left)) {
        _dash(canvas, rect.topLeft, rect.bottomLeft, paint);
      }
    }
  }

  void _dash(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DropRegionOutlinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.coords.scale != coords.scale ||
        oldDelegate.coords.panOffset != coords.panOffset ||
        !_sameCells(oldDelegate.cells, cells);
  }

  bool _sameCells(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
