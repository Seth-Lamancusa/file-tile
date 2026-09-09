import 'package:flutter/material.dart';

/// Dotted cell + drop glyph for an incoming OS file drop.
class OsDropTargetOverlay extends StatelessWidget {
  final Rect cellScreenRect;
  final Color color;

  const OsDropTargetOverlay({
    super.key,
    required this.cellScreenRect,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: cellScreenRect,
            child: CustomPaint(
              painter: _DashedRectPainter(color: color),
              child: Center(
                child: Icon(
                  Icons.note_add_outlined,
                  color: color,
                  size: (cellScreenRect.shortestSide * 0.4).clamp(16.0, 36.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;

  _DashedRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 6.0;
    const gap = 4.0;
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final path = Path()..addRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
