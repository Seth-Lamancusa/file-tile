import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Shifts [preferred] so a menu of [menuSize] stays inside the padded viewport.
Offset fitMenuToViewport({
  required Offset preferred,
  required Size menuSize,
  required Size viewportSize,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return _clampOrigin(
    preferred: preferred,
    menuSize: menuSize,
    viewportSize: viewportSize,
    padding: padding,
  );
}

/// Places a submenu beside [anchor]: to the right if it fits, otherwise the
/// left, then clamps so it stays on screen.
Offset fitSubmenuToViewport({
  required Rect anchor,
  required Size menuSize,
  required Size viewportSize,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  final left = padding.left;
  final right = viewportSize.width - padding.right;

  var x = anchor.right;
  if (x + menuSize.width > right && anchor.left - menuSize.width >= left) {
    x = anchor.left - menuSize.width;
  }

  return _clampOrigin(
    preferred: Offset(x, anchor.top),
    menuSize: menuSize,
    viewportSize: viewportSize,
    padding: padding,
  );
}

Offset _clampOrigin({
  required Offset preferred,
  required Size menuSize,
  required Size viewportSize,
  required EdgeInsets padding,
}) {
  final minX = padding.left;
  final minY = padding.top;
  final maxX = viewportSize.width - padding.right - menuSize.width;
  final maxY = viewportSize.height - padding.bottom - menuSize.height;
  return Offset(
    preferred.dx.clamp(minX, math.max(minX, maxX)),
    preferred.dy.clamp(minY, math.max(minY, maxY)),
  );
}
