import 'package:file_tile/src/utils/edge_auto_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const canvas = Size(800, 600);

  test('pointer in the middle of the canvas does not pan', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: const Offset(400, 300),
        canvasSize: canvas,
      ),
      Offset.zero,
    );
  });

  test('left edge pans the view left by moving content right', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: const Offset(10, 300),
        canvasSize: canvas,
      ),
      const Offset(EdgeAutoScroll.maxSpeed, 0),
    );
  });

  test('right edge pans the view right by moving content left', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: const Offset(790, 300),
        canvasSize: canvas,
      ),
      const Offset(-EdgeAutoScroll.maxSpeed, 0),
    );
  });

  test('top edge pans the view up by moving content down', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: const Offset(400, 0),
        canvasSize: canvas,
      ),
      const Offset(0, EdgeAutoScroll.maxSpeed),
    );
  });

  test('bottom edge pans the view down by moving content up', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: const Offset(400, 590),
        canvasSize: canvas,
      ),
      const Offset(0, -EdgeAutoScroll.maxSpeed),
    );
  });

  test('speed falls off linearly across the outer edge zone', () {
    final delta = EdgeAutoScroll.delta(
      canvasLocal: const Offset(40, 300),
      canvasSize: canvas,
    );
    expect(delta.dx, closeTo(EdgeAutoScroll.maxSpeed / 2, 0.001));
    expect(delta.dy, 0);
  });

  test('pointer just outside the zone does not pan', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: const Offset(EdgeAutoScroll.edgeZoneMax, 300),
        canvasSize: canvas,
      ),
      Offset.zero,
    );
  });

  test('a corner pans on both axes', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: Offset.zero,
        canvasSize: canvas,
      ),
      const Offset(EdgeAutoScroll.maxSpeed, EdgeAutoScroll.maxSpeed),
    );
  });

  test('when both edges are inside the zone, the leading edge wins', () {
    // 50px from the left, 5px from the right. The right edge is deeper in
    // the zone, but the left edge is still inside it and takes priority.
    final delta = EdgeAutoScroll.delta(
      canvasLocal: const Offset(50, 50),
      canvasSize: const Size(55, 55),
    );
    expect(delta.dx, closeTo(EdgeAutoScroll.maxSpeed * 0.25, 0.001));
    expect(delta.dy, closeTo(EdgeAutoScroll.maxSpeed * 0.25, 0.001));
  });

  test('an empty canvas does not pan', () {
    expect(
      EdgeAutoScroll.delta(
        canvasLocal: Offset.zero,
        canvasSize: Size.zero,
      ),
      Offset.zero,
    );
  });
}
