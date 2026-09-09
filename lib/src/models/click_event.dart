import 'dart:ui' show Offset;

import 'package:flutter/services.dart';

/// Encapsulates keyboard modifier state at the moment of a click.
class ClickModifiers {
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  const ClickModifiers({
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// Factory to extract modifiers from HardwareKeyboard at click time.
  factory ClickModifiers.fromHardwareKeyboard() {
    final keyboard = HardwareKeyboard.instance;
    return ClickModifiers(
      ctrl: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClickModifiers &&
          runtimeType == other.runtimeType &&
          ctrl == other.ctrl &&
          shift == other.shift &&
          alt == other.alt &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(ctrl, shift, alt, meta);

  @override
  String toString() =>
      'ClickModifiers(ctrl: $ctrl, shift: $shift, alt: $alt, meta: $meta)';
}

/// The semantic intent of a click based on modifier state.
/// These are the actions that the grid supports for node selection.
enum ClickAction {
  /// Standard click: select only this node, deselect all others.
  selectSingle,

  /// Ctrl+click: toggle this node's selection state.
  toggleSelect,

  /// Shift+click: select a rectangular range from last-selected to this node.
  rangeSelect,

  /// Clicks on empty canvas or multi-modifier combos not mapped to any action.
  noOp,
}

/// Result of hit testing a click event.
sealed class ClickResult {
  /// The logical position where the click occurred (before snapping).
  final Offset logicalPosition;

  ClickResult({required this.logicalPosition});
}

/// Click hit a node; ClickHandler has already dispatched selection action.
class NodeClickResult extends ClickResult {
  final String nodeId;
  final ClickAction action;

  NodeClickResult({
    required this.nodeId,
    required this.action,
    required super.logicalPosition,
  });
}

/// Click hit empty canvas.
class BackgroundClickResult extends ClickResult {
  final ClickAction action;

  BackgroundClickResult({
    required this.action,
    required super.logicalPosition,
  });
}
