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
        canvas.drawRect(rect, Paint()..color = regionColor.withValues(alpha: baseOpacity));
      }

      // Draw unconstrained direction cells (vertical with fade)
      // Build a sequence of valid grid indices (skipping 0)
      final fadeRows = <int>[];
      int row = config.anchorRow;
      for (int i = 0; i < fadeOutCells; i++) {
        // Move to next valid grid index
        if (config.unconstrainedDirection == 'down') {
          row = row < 0 ? (row + 1 == 0 ? 1 : row + 1) : row + 1;
        } else {
          row = row > 0 ? (row - 1 == 0 ? -1 : row - 1) : row - 1;
        }
        fadeRows.add(row);
      }

      for (int i = 0; i < fadeRows.length; i++) {
        final row = fadeRows[i];
        final opacity = (1.0 - ((i + 1) / (fadeOutCells + 1))) * baseOpacity;

        for (int j = 0; j < config.constrainedCount; j++) {
          final col = config.constrainedDirection == 'right'
              ? config.anchorCol + j
              : config.anchorCol - j;

          final cellLogicalX = col > 0 ? (col - 1) * gridSize : col * gridSize;
          final cellLogicalY = row > 0 ? (row - 1) * gridSize : row * gridSize;
          final cellScreenPos = coords.logicalToScreen(Offset(cellLogicalX, cellLogicalY));

          final cellSize = coords.renderedGridCellSize;
          final rect = Rect.fromLTWH(cellScreenPos.dx, cellScreenPos.dy, cellSize, cellSize);
          canvas.drawRect(rect, Paint()..color = regionColor.withValues(alpha: opacity));
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
        canvas.drawRect(rect, Paint()..color = regionColor.withValues(alpha: baseOpacity));
      }

      // Draw unconstrained direction cells (horizontal with fade)
      // Build a sequence of valid grid indices (skipping 0)
      final fadeCols = <int>[];
      int col = config.anchorCol;
      for (int i = 0; i < fadeOutCells; i++) {
        // Move to next valid grid index
        if (config.unconstrainedDirection == 'right') {
          col = col < 0 ? (col + 1 == 0 ? 1 : col + 1) : col + 1;
        } else {
          col = col > 0 ? (col - 1 == 0 ? -1 : col - 1) : col - 1;
        }
        fadeCols.add(col);
      }

      for (int i = 0; i < fadeCols.length; i++) {
        final col = fadeCols[i];
        final opacity = (1.0 - ((i + 1) / (fadeOutCells + 1))) * baseOpacity;

        for (int j = 0; j < config.constrainedCount; j++) {
          final row = config.constrainedDirection == 'down'
              ? config.anchorRow + j
              : config.anchorRow - j;

          final cellLogicalX = col > 0 ? (col - 1) * gridSize : col * gridSize;
          final cellLogicalY = row > 0 ? (row - 1) * gridSize : row * gridSize;
          final cellScreenPos = coords.logicalToScreen(Offset(cellLogicalX, cellLogicalY));

          final cellSize = coords.renderedGridCellSize;
          final rect = Rect.fromLTWH(cellScreenPos.dx, cellScreenPos.dy, cellSize, cellSize);
          canvas.drawRect(rect, Paint()..color = regionColor.withValues(alpha: opacity));
        }
      }
    }
  }

  @override
  bool shouldRepaint(PlacementRegionPainter oldDelegate) {
    return config != oldDelegate.config ||
        coords != oldDelegate.coords ||
        maxRowsOrColsToShow != oldDelegate.maxRowsOrColsToShow;
  }
}
