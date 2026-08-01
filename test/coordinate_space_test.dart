import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitch_desktop_grid/src/utils/coordinate_space.dart';

void main() {
  group('CoordinateSpace', () {
    test('screenToLogical and logicalToScreen are inverses', () {
      const cs = CoordinateSpace(scale: 2.0, panOffset: Offset(100, 200));
      final logicalPos = Offset(50, 60);

      final screenPos = cs.logicalToScreen(logicalPos);
      final backToLogical = cs.screenToLogical(screenPos);

      expect(backToLogical.dx, closeTo(logicalPos.dx, 0.0001));
      expect(backToLogical.dy, closeTo(logicalPos.dy, 0.0001));
    });

    test('screenToLogical converts with pan and zoom', () {
      const cs = CoordinateSpace(scale: 2.0, panOffset: Offset(100, 200));

      // Screen position (100, 200) with pan offset (100, 200) and scale 2.0
      // Should give logical position (0, 0)
      final logicalPos = cs.screenToLogical(const Offset(100, 200));

      expect(logicalPos.dx, 0.0);
      expect(logicalPos.dy, 0.0);
    });

    test('screenToLogical at (200, 400) with pan (100, 200) and zoom 2x gives (50, 100)', () {
      const cs = CoordinateSpace(scale: 2.0, panOffset: Offset(100, 200));
      final logicalPos = cs.screenToLogical(const Offset(200, 400));

      expect(logicalPos.dx, 50.0);
      expect(logicalPos.dy, 100.0);
    });

    test('logicalToGridIndices returns correct 1-based cell indices', () {
      const cs = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);
      // Grid cell size is 80 logical pixels, 1-indexed, no zero

      // Positive side: 0-79 is cell 1, 80-159 is cell 2
      final (x1, y1) = cs.logicalPosToGridIndices(const Offset(40, 50));
      expect(x1, 1);
      expect(y1, 1);

      final (x2, y1b) = cs.logicalPosToGridIndices(const Offset(80, 50));
      expect(x2, 2);
      expect(y1b, 1);

      final (x2b, y2) = cs.logicalPosToGridIndices(const Offset(80, 80));
      expect(x2b, 2);
      expect(y2, 2);

      // Negative side: -1 to -80 is cell -1, -81 to -160 is cell -2
      final (xNeg1, yNeg1) = cs.logicalPosToGridIndices(const Offset(-40, -50));
      expect(xNeg1, -1);
      expect(yNeg1, -1);

      final (xNeg1b, yNeg2) = cs.logicalPosToGridIndices(const Offset(-1, -80));
      expect(xNeg1b, -1);
      expect(yNeg2, -1);

      final (xNeg2, yNeg2b) = cs.logicalPosToGridIndices(const Offset(-81, -100));
      expect(xNeg2, -2);
      expect(yNeg2b, -2);
    });

    test('snapToNearestGridCell snaps to grid lines', () {
      const cs = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);

      // 0-40 should snap to nearest line: 0
      expect(
        cs.snapToNearestGridCell(const Offset(20, 30)),
        const Offset(0, 0),
      );

      // 40-120 should snap to nearest line: 80
      expect(
        cs.snapToNearestGridCell(const Offset(50, 100)),
        const Offset(80, 80),
      );

      // 120+ should snap to nearest line: 160
      expect(
        cs.snapToNearestGridCell(const Offset(150, 150)),
        const Offset(160, 160),
      );
    });

    test('snapToCellCorner snaps to cell lower-bound corner (grid-aligned)', () {
      const cs = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);

      // Position (40, 50) is in cell (1, 1) [0, 80) → corner at (0, 0)
      expect(
        cs.snapToCellCorner(const Offset(40, 50)),
        const Offset(0, 0),
      );

      // Position (100, 100) is in cell (2, 2) [80, 160) → corner at (80, 80)
      expect(
        cs.snapToCellCorner(const Offset(100, 100)),
        const Offset(80, 80),
      );

      // Position (294.1, -93.3) is in cell (4, -2) [240, 320) x [-160, -80) → corner at (240, -160)
      expect(
        cs.snapToCellCorner(const Offset(294.1, -93.3)),
        const Offset(240, -160),
      );

      // Negative position (-50, -50) is in cell (-1, -1) [-80, 0) → corner at (-80, -80)
      expect(
        cs.snapToCellCorner(const Offset(-50, -50)),
        const Offset(-80, -80),
      );
    });

    test('renderedGridCellSize accounts for zoom', () {
      const cs1x = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);
      const cs2x = CoordinateSpace(scale: 2.0, panOffset: Offset.zero);
      const cs05x = CoordinateSpace(scale: 0.5, panOffset: Offset.zero);

      expect(cs1x.renderedGridCellSize, 80.0);
      expect(cs2x.renderedGridCellSize, 160.0);
      expect(cs05x.renderedGridCellSize, 40.0);
    });

    test('screenDeltaToLogicalDelta handles zoom correctly', () {
      const cs = CoordinateSpace(scale: 2.0, panOffset: Offset.zero);

      // 10 pixels on screen at 2x zoom = 5 logical pixels
      final logicalDelta = cs.screenDeltaToLogicalDelta(const Offset(10, 20));

      expect(logicalDelta.dx, 5.0);
      expect(logicalDelta.dy, 10.0);
    });
  });

  group('GridConfig', () {
    test('gridCellSize and renderGridSize are configured correctly', () {
      expect(GridConfig.gridCellSize, 80.0);
      expect(GridConfig.renderGridSize, 40.0);
      expect(GridConfig.isValid, true);
    });
  });
}
