import 'package:flutter/material.dart';

/// Manages selection state for nodes in the grid.
/// This is separate from DesktopViewModel to keep selection logic testable and reusable.
class SelectionController extends ChangeNotifier {
  final Set<String> _selected = {};

  Set<String> get selected => Set.unmodifiable(_selected);

  bool isSelected(String nodeId) => _selected.contains(nodeId);

  int get selectionCount => _selected.length;

  /// Select a single node, clearing all others.
  void selectSingle(String nodeId) {
    if (_selected.length == 1 && _selected.contains(nodeId)) {
      // Already the only selection; no change.
      return;
    }
    _selected.clear();
    _selected.add(nodeId);
    notifyListeners();
  }

  /// Toggle a node's selection state (add if absent, remove if present).
  void toggleSelect(String nodeId) {
    final wasSelected = _selected.contains(nodeId);
    if (wasSelected) {
      _selected.remove(nodeId);
    } else {
      _selected.add(nodeId);
    }
    notifyListeners();
  }

  /// Select a rectangular range of nodes between two coordinates.
  /// [startNodeId] and [endNodeId] should map to their positions in the grid.
  /// For now, this is a placeholder; the caller (view) will determine which nodes
  /// fall within the bounding box and call this method with the IDs.
  void rangeSelect(List<String> nodeIds) {
    if (nodeIds.isEmpty) return;
    _selected.clear();
    _selected.addAll(nodeIds);
    notifyListeners();
  }

  /// Clear all selections.
  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Replace the entire selection with a new set.
  /// Useful for bulk operations or when state comes from an external source.
  void setSelection(Set<String> nodeIds) {
    _selected.clear();
    _selected.addAll(nodeIds);
    notifyListeners();
  }
}
