import 'dart:ui';

/// Screen-space pan while a drag pointer rests near a canvas edge.
///
/// The inner [edgeZoneMin] pixels of an edge scroll at [maxSpeed] per [tick].
/// Speed falls off linearly and reaches zero at [edgeZoneMax]. A positive
/// delta moves canvas content down or to the right, revealing what lies past
/// the edge the pointer is against.
class EdgeAutoScroll {
  static const double maxSpeed = 17;
  static const double edgeZoneMin = 20;
  static const double edgeZoneMax = 60;
  static const Duration tick = Duration(milliseconds: 16);

  static Offset delta({
    required Offset canvasLocal,
    required Size canvasSize,
  }) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return Offset.zero;
    return Offset(
      _axis(canvasLocal.dx, canvasSize.width - canvasLocal.dx),
      _axis(canvasLocal.dy, canvasSize.height - canvasLocal.dy),
    );
  }

  /// Leading edge wins when the canvas is narrower than both zones.
  static double _axis(double leading, double trailing) {
    if (leading < edgeZoneMax) return _ramp(leading) * maxSpeed;
    if (trailing < edgeZoneMax) return -_ramp(trailing) * maxSpeed;
    return 0;
  }

  static double _ramp(double distance) {
    if (distance <= edgeZoneMin) return 1;
    if (distance >= edgeZoneMax) return 0;
    return (edgeZoneMax - distance) / (edgeZoneMax - edgeZoneMin);
  }
}
