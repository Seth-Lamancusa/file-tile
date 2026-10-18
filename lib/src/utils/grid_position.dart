import 'package:flutter/material.dart';
import '../viewmodels/desktop_viewmodel.dart';

/// Sides of a grid cell that form the outer edge of a region.
enum CellOutlineSide { top, right, bottom, left }

/// Sides of [cell] that are not shared with another cell in [cells].
/// Adjacent cells drop the shared edge so a region reads as one outline.
/// Cells that do not touch keep a full outline, so the region may be disjoint.
Set<CellOutlineSide> outerCellOutlineSides(
  Offset cell,
  Iterable<Offset> cells,
  double cellSize,
) {
  final sides = CellOutlineSide.values.toSet();
  for (final other in cells) {
    if (other == cell) continue;
    final dx = other.dx - cell.dx;
    final dy = other.dy - cell.dy;
    const tolerance = 1.0;
    if ((dy + cellSize).abs() < tolerance && dx.abs() < tolerance) {
      sides.remove(CellOutlineSide.top);
    } else if ((dx - cellSize).abs() < tolerance && dy.abs() < tolerance) {
      sides.remove(CellOutlineSide.right);
    } else if ((dy - cellSize).abs() < tolerance && dx.abs() < tolerance) {
      sides.remove(CellOutlineSide.bottom);
    } else if ((dx + cellSize).abs() < tolerance && dy.abs() < tolerance) {
      sides.remove(CellOutlineSide.left);
    }
  }
  return sides;
}

/// Check if a single position is available (not occupied).
bool isPositionAvailable(Offset position, Set<Offset> occupiedPositions) {
  return !occupiedPositions.contains(position);
}

/// Get all occupied positions from a list of nodes, optionally excluding specific nodes.
Set<Offset> getOccupiedPositions(
  List<DesktopNode> allNodes, {
  Set<String>? excludeNames,
}) {
  return allNodes
      .where((n) => excludeNames == null || !excludeNames.contains(n.name))
      .map((n) => n.position)
      .toSet();
}

/// Check if a set of desired positions can be placed without collision.
/// Returns false if any desired position overlaps with occupied positions,
/// or if the desired positions overlap with each other.
bool canPlaceNodes(
  List<Offset> desiredPositions,
  Set<Offset> occupiedPositions,
) {
  // Check if any desired position collides with occupied positions
  for (final pos in desiredPositions) {
    if (occupiedPositions.contains(pos)) {
      return false;
    }
  }

  // Check if desired positions collide with each other
  if (desiredPositions.toSet().length != desiredPositions.length) {
    return false;
  }

  return true;
}

/// Find the next available grid position starting from a desired position.
/// Wraps after [maxColumnsBeforeWrap] columns, then moves to the next row.
/// Returns the desired position if available, otherwise searches sequentially.
Offset findNextAvailablePosition(
  Offset desired,
  Set<Offset> occupiedPositions,
  double gridSize,
  int maxColumnsBeforeWrap,
) {
  // Snap desired to grid
  double x = (desired.dx / gridSize).round() * gridSize;
  double y = (desired.dy / gridSize).round() * gridSize;

  // Search for next available position
  while (true) {
    if (isPositionAvailable(Offset(x, y), occupiedPositions)) {
      return Offset(x, y);
    }

    // Move to next grid cell
    x += gridSize;

    // Wrap to next row
    final columnsUsed = (x / gridSize).round();
    if (columnsUsed >= maxColumnsBeforeWrap) {
      x = 0;
      y += gridSize;
    }
  }
}
