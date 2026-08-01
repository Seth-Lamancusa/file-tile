import 'package:flutter/material.dart';
import '../models/new_element_placement_config.dart';
import '../utils/coordinate_space.dart';

class PlacementRegionPainter extends CustomPainter {
  final NewElementPlacementConfig config;
  final CoordinateSpace coords;
  final int maxRowsOrColsToShow;

  PlacementRegionPainter({
    required this.config,
    required this.coords,
    this.maxRowsOrColsToShow = 20,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const gridSize = GridConfig.gridCellSize;
    const regionColor = Color(0xFF2A7EDF); // Blue
    const baseOpacity = 0.15; // Much more transparent
    const textOpacity = 0.3;
    const textColor = Color(0xFFFFFFFF); // White

    // Convert grid anchor to logical pixels (using 1-based indexing for positive)
    final anchorLogicalX = config.anchorCol > 0
        ? (config.anchorCol - 1) * gridSize
        : config.anchorCol * gridSize;
    final anchorLogicalY = config.anchorRow > 0
        ? (config.anchorRow - 1) * gridSize
        : config.anchorRow * gridSize;

    final isConstrainedHorizontal = config.isConstrainedAxisColumns;
    const fadeOutCells = 5;

    if (isConstrainedHorizontal) {
      // Constrained direction is horizontal (left/right)
      // Draw the constrained (horizontal) line
      for (int i = 0; i < config.constrainedCount; i++) {
        final col = config.constrainedDirection == 'right'
            ? config.anchorCol + i
            : config.anchorCol - i;
        final cellLogicalX = col > 0 ? (col - 1) * gridSize : col * gridSize;
        final cellLogicalY = config.anchorRow > 0
            ? (config.anchorRow - 1) * gridSize
            : config.anchorRow * gridSize;
        final cellScreenPos = coords.logicalToScreen(Offset(cellLogicalX, cellLogicalY));

        final cellSize = coords.renderedGridCellSize;
        final rect = Rect.fromLTWH(cellScreenPos.dx, cellScreenPos.dy, cellSize, cellSize);
        canvas.drawRect(rect, Paint()..color = regionColor.withOpacity(baseOpacity));
      }

      // Draw unconstrained direction cells (vertical with fade)
      for (int i = 1; i <= fadeOutCells; i++) {
        final row = config.unconstrainedDirection == 'down'
            ? config.anchorRow + i
            : config.anchorRow - i;

        // Fade out as we go further from anchor
        final opacity = (1.0 - (i / (fadeOutCells + 1))) * baseOpacity;

        for (int j = 0; j < config.constrainedCount; j++) {
          final col = config.constrainedDirection == 'right'
              ? config.anchorCol + j
              : config.anchorCol - j;

          final cellLogicalX = col > 0 ? (col - 1) * gridSize : col * gridSize;
          final cellLogicalY = row > 0 ? (row - 1) * gridSize : row * gridSize;
          final cellScreenPos = coords.logicalToScreen(Offset(cellLogicalX, cellLogicalY));

          final cellSize = coords.renderedGridCellSize;
          final rect = Rect.fromLTWH(cellScreenPos.dx, cellScreenPos.dy, cellSize, cellSize);
          canvas.drawRect(rect, Paint()..color = regionColor.withOpacity(opacity));
        }
      }
    } else {
      // Constrained direction is vertical (up/down)
      // Draw the constrained (vertical) line
      for (int i = 0; i < config.constrainedCount; i++) {
        final row = config.constrainedDirection == 'down'
            ? config.anchorRow + i
            : config.anchorRow - i;
        final cellLogicalX = config.anchorCol > 0
            ? (config.anchorCol - 1) * gridSize
            : config.anchorCol * gridSize;
        final cellLogicalY = row > 0 ? (row - 1) * gridSize : row * gridSize;
        final cellScreenPos = coords.logicalToScreen(Offset(cellLogicalX, cellLogicalY));

        final cellSize = coords.renderedGridCellSize;
        final rect = Rect.fromLTWH(cellScreenPos.dx, cellScreenPos.dy, cellSize, cellSize);
        canvas.drawRect(rect, Paint()..color = regionColor.withOpacity(baseOpacity));
      }

      // Draw unconstrained direction cells (horizontal with fade)
      for (int i = 1; i <= fadeOutCells; i++) {
        final col = config.unconstrainedDirection == 'right'
            ? config.anchorCol + i
            : config.anchorCol - i;

        // Fade out as we go further from anchor
        final opacity = (1.0 - (i / (fadeOutCells + 1))) * baseOpacity;

        for (int j = 0; j < config.constrainedCount; j++) {
          final row = config.constrainedDirection == 'down'
              ? config.anchorRow + j
              : config.anchorRow - j;

          final cellLogicalX = col > 0 ? (col - 1) * gridSize : col * gridSize;
          final cellLogicalY = row > 0 ? (row - 1) * gridSize : row * gridSize;
          final cellScreenPos = coords.logicalToScreen(Offset(cellLogicalX, cellLogicalY));

          final cellSize = coords.renderedGridCellSize;
          final rect = Rect.fromLTWH(cellScreenPos.dx, cellScreenPos.dy, cellSize, cellSize);
          canvas.drawRect(rect, Paint()..color = regionColor.withOpacity(opacity));
        }
      }
    }

    // Draw text hint
    // _drawTextHint(canvas, size, isConstrainedHorizontal, anchorLogicalX, anchorLogicalY, gridSize, fadeOutCells, textColor, textOpacity);
  }

  void _drawTextHint(
    Canvas canvas,
    Size size,
    bool isConstrainedHorizontal,
    double anchorLogicalX,
    double anchorLogicalY,
    double gridSize,
    int fadeOutCells,
    Color textColor,
    double textOpacity,
  ) {
    const text = 'New files and folders will populate here.';
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor.withOpacity(textOpacity),
          fontSize: 12 * coords.scale,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Calculate text position based on unconstrained direction
    const textPadding = 8.0;
    late Offset textPos;
    if (isConstrainedHorizontal) {
      // Constrained is horizontal, unconstrained is vertical
      final textX = anchorLogicalX + textPadding;
      if (config.unconstrainedDirection == 'down') {
        // Extend downward: place text at top of anchor cell
        textPos = coords.logicalToScreen(Offset(textX, anchorLogicalY + textPadding));
      } else {
        // Extend upward: place text at bottom of anchor cell
        final textLogicalY = anchorLogicalY + gridSize - textPadding - 20;
        textPos = coords.logicalToScreen(Offset(textX, textLogicalY));
      }
    } else {
      // Constrained is vertical, unconstrained is horizontal
      final textY = anchorLogicalY + textPadding;
      if (config.unconstrainedDirection == 'right') {
        // Extend rightward: place text at left of anchor cell
        textPos = coords.logicalToScreen(Offset(anchorLogicalX + textPadding, textY));
      } else {
        // Extend leftward: place text at right of anchor cell
        final textLogicalX = anchorLogicalX + gridSize - textPadding;
        textPos = coords.logicalToScreen(Offset(textLogicalX, textY));
      }
    }

    textPainter.paint(canvas, textPos);
  }

  @override
  bool shouldRepaint(PlacementRegionPainter oldDelegate) {
    return config != oldDelegate.config ||
        coords != oldDelegate.coords ||
        maxRowsOrColsToShow != oldDelegate.maxRowsOrColsToShow;
  }
}
