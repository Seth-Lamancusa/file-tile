import 'package:flutter/material.dart';

/// Configuration for the grid layout system.
/// Grid cells are always [gridCellSize] × [gridCellSize] logical pixels.
/// The visual reference grid is rendered at [renderGridSize] intervals.
class GridConfig {
  static const double gridCellSize = 80.0;
  static const double renderGridSize = 40.0;

  // Validate that render grid divides evenly into cell size
  static const bool isValid = gridCellSize % renderGridSize == 0;
}

/// Configuration for the application UI layout.
class AppConfig {
  static const double appBarHeight = 40.0;
}

/// Encapsulates all coordinate transformations between screen and logical grid space.
///
/// **Coordinate spaces:**
/// - **Screen space**: pixels on the window (affected by pan offset and zoom)
/// - **Logical space**: abstract grid coordinates (unaffected by pan/zoom, the "true" position)
///
/// All method names explicitly indicate input and output spaces to avoid confusion.
class CoordinateSpace {
  final double scale;
  final Offset panOffset;

  const CoordinateSpace({required this.scale, required this.panOffset});

  /// Convert screen pixels to logical grid space.
  ///
  /// Example: user clicks at screen position (100, 200), which is at pan offset (50, 60)
  /// with zoom 2.0 → logical position is ((100, 200) - (50, 60)) / 2.0 = (25, 70).
  Offset screenToLogical(Offset screenPos) {
    return (screenPos - panOffset) / scale;
  }

  /// Convert logical grid space to screen pixels.
  /// Inverse of [screenToLogical].
  Offset logicalToScreen(Offset logicalPos) {
    return panOffset + (logicalPos * scale);
  }

  /// Convert a screen-space delta to logical-space delta (useful for drag handling).
  /// Does NOT account for pan offset (only zoom), since deltas are relative.
  Offset screenDeltaToLogicalDelta(Offset screenDelta) {
    return screenDelta / scale;
  }

  /// Determine which grid cell indices a logical position falls into.
  ///
  /// Returns (gridX, gridY) using 1-based indexing with no zero:
  /// - (1, 1) is the first cell (0–79 pixels)
  /// - (2, 1) is the second cell horizontally (80–159 pixels)
  /// - (-1, 1) is one cell to the left (-80 to -1 pixels)
  /// - (-2, 1) is two cells to the left (-160 to -81 pixels)
  ///
  /// Example: logical position (120, 200) with gridCellSize=80 → (2, 3)
  (int gridX, int gridY) logicalPosToGridIndices(Offset logicalPos) {
    final gridX = logicalPos.dx >= 0
        ? (logicalPos.dx / GridConfig.gridCellSize).floor() + 1
        : (logicalPos.dx / GridConfig.gridCellSize).floor();
    final gridY = logicalPos.dy >= 0
        ? (logicalPos.dy / GridConfig.gridCellSize).floor() + 1
        : (logicalPos.dy / GridConfig.gridCellSize).floor();
    return (gridX.toInt(), gridY.toInt());
  }

  /// Snap to the nearest grid line (corner of cell).
  /// Rounds to the nearest multiple of gridCellSize.
  ///
  /// Example: logical position (294.1, -93.3) → snaps to (320, -80)
  /// Note: This may move the position into an adjacent cell.
  Offset snapToNearestGridCell(Offset logicalPos) {
    final gridX = (logicalPos.dx / GridConfig.gridCellSize).round();
    final gridY = (logicalPos.dy / GridConfig.gridCellSize).round();
    return Offset(
      gridX * GridConfig.gridCellSize,
      gridY * GridConfig.gridCellSize,
    );
  }

  /// Snap to the lower-bound corner of the grid cell containing this position.
  /// Ensures the item aligns to the logical grid while staying in the clicked cell.
  ///
  /// Example: logical position (294.1, -93.3) in cell (4, -2) → snaps to (240, -160)
  /// Cell (4, -2) occupies [240, 320) × [-160, -80), snapping to the starting corner.
  Offset snapToCellCorner(Offset logicalPos) {
    final (gridX, gridY) = logicalPosToGridIndices(logicalPos);

    // Calculate cell's lower-bound corner from grid indices
    // For positive cells N: occupies [(N-1)*size, N*size), corner at (N-1)*size
    // For negative cells -N: occupies [-(N*size), -(N-1)*size), corner at -N*size
    final cornerX = gridX > 0
        ? (gridX - 1) * GridConfig.gridCellSize
        : gridX * GridConfig.gridCellSize;

    final cornerY = gridY > 0
        ? (gridY - 1) * GridConfig.gridCellSize
        : gridY * GridConfig.gridCellSize;

    return Offset(cornerX, cornerY);
  }

  /// Screen size of one grid cell at current zoom level.
  /// Useful for sizing UI elements that should scale with zoom.
  ///
  /// Example: at 2x zoom, gridCellSize = 80 → renderedGridCellSize = 160 screen pixels.
  double get renderedGridCellSize => GridConfig.gridCellSize * scale;

  /// Screen size of the visual reference grid at current zoom level.
  /// The visual grid is drawn at this interval on screen.
  ///
  /// Example: at 0.5x zoom, renderGridSize = 40 → renderedReferenceGridSize = 20 screen pixels.
  double get renderedReferenceGridSize => GridConfig.renderGridSize * scale;
}
