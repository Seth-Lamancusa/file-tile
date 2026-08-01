import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/click_event.dart';
import '../utils/coordinate_space.dart';
import 'selection_controller.dart';

/// Represents a node for the purposes of hit detection.
class HitTestNode {
  final String id;
  final Offset position;
  final double size;

  const HitTestNode({
    required this.id,
    required this.position,
    required this.size,
  });

  /// Check if a point (in screen space) is within this node's bounds.
  bool hitsPoint(Offset screenPoint, CoordinateSpace coords) {
    final screenPos = coords.logicalToScreen(position);
    final scaledSize = size * coords.scale;

    final rect = Rect.fromLTWH(screenPos.dx, screenPos.dy, scaledSize, scaledSize);
    return rect.contains(screenPoint);
  }
}

/// Handles click events and delegates to the SelectionController.
/// Decoupled from the view layer so it can be tested independently.
class ClickHandler {
  final SelectionController selectionController;

  ClickHandler({required this.selectionController});

  /// Process a primary (left) click event on the canvas.
  /// Performs hit testing and dispatches selection actions via selectionController.
  /// Returns a ClickResult indicating what was hit and what action was taken.
  ClickResult handlePrimaryPointerDown({
    required Offset screenPosition,
    required List<HitTestNode> nodes,
    required CoordinateSpace coords,
  }) {
    final modifiers = ClickModifiers.fromHardwareKeyboard();
    final action = ClickActionMapper.mapModifiersToAction(modifiers);
    final logicalPos = coords.screenToLogical(screenPosition);

    // Find which node (if any) was clicked.
    String? clickedNodeId;
    for (final node in nodes) {
      if (node.hitsPoint(screenPosition, coords)) {
        clickedNodeId = node.id;
        break;
      }
    }

    if (clickedNodeId == null) {
      // Click on empty canvas: deselect all.
      if (action == ClickAction.selectSingle) {
        selectionController.clearSelection();
      }
      return BackgroundClickResult(action: action, logicalPosition: logicalPos);
    }

    // A node was clicked; dispatch based on action.
    switch (action) {
      case ClickAction.selectSingle:
        // Always select single, even if already selected (deselect other items in multi-selection)
        selectionController.selectSingle(clickedNodeId);
        break;
      case ClickAction.toggleSelect:
        selectionController.toggleSelect(clickedNodeId);
        break;
      case ClickAction.rangeSelect:
        _handleRangeSelect(clickedNodeId, nodes);
        break;
      case ClickAction.noOp:
        break;
    }

    return NodeClickResult(
      nodeId: clickedNodeId,
      action: action,
      logicalPosition: logicalPos,
    );
  }

  /// Process a secondary (right) click event for context menus.
  /// Performs hit testing and selects the clicked node (deselecting others).
  /// Returns a ClickResult indicating what was hit (used to show appropriate context menu).
  ClickResult handleSecondaryPointerDown({
    required Offset screenPosition,
    required List<HitTestNode> nodes,
    required CoordinateSpace coords,
  }) {
    final logicalPos = coords.screenToLogical(screenPosition);

    // Find which node (if any) was clicked.
    String? clickedNodeId;
    for (final node in nodes) {
      if (node.hitsPoint(screenPosition, coords)) {
        clickedNodeId = node.id;
        break;
      }
    }

    if (clickedNodeId == null) {
      return BackgroundClickResult(
        action: ClickAction.noOp,
        logicalPosition: logicalPos,
      );
    }

    // Select the right-clicked node, deselecting all others
    selectionController.selectSingle(clickedNodeId);

    return NodeClickResult(
      nodeId: clickedNodeId,
      action: ClickAction.noOp,
      logicalPosition: logicalPos,
    );
  }

  /// Handle range selection (Shift+click).
  /// Selects all nodes within the bounding box defined by the current selection
  /// and the newly clicked node.
  void _handleRangeSelect(String newNodeId, List<HitTestNode> nodes) {
    if (selectionController.selected.isEmpty) {
      // No prior selection; treat as single select.
      selectionController.selectSingle(newNodeId);
      return;
    }

    // Find bounding box of current selection + new node.
    final nodesToConsider = nodes.where(
      (n) => selectionController.selected.contains(n.id) || n.id == newNodeId,
    );

    if (nodesToConsider.isEmpty) {
      selectionController.selectSingle(newNodeId);
      return;
    }

    double minX = nodesToConsider.first.position.dx;
    double maxX = minX;
    double minY = nodesToConsider.first.position.dy;
    double maxY = minY;

    for (final node in nodesToConsider) {
      minX = math.min(minX, node.position.dx);
      maxX = math.max(maxX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxY = math.max(maxY, node.position.dy);
    }

    // Find all nodes within this bounding box.
    final inRange = nodes
        .where((n) =>
            n.position.dx >= minX &&
            n.position.dx <= maxX &&
            n.position.dy >= minY &&
            n.position.dy <= maxY)
        .map((n) => n.id)
        .toList();

    selectionController.rangeSelect(inRange);
  }
}
