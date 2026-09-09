import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_tile/src/utils/menu_position.dart';

void main() {
  const viewport = Size(800, 600);

  group('fitMenuToViewport', () {
    test('keeps a menu that already fits at the click position', () {
      expect(
        fitMenuToViewport(
          preferred: const Offset(40, 50),
          menuSize: const Size(200, 100),
          viewportSize: viewport,
        ),
        const Offset(40, 50),
      );
    });

    test('shifts left and up when the menu would overflow the right or bottom',
        () {
      expect(
        fitMenuToViewport(
          preferred: const Offset(700, 550),
          menuSize: const Size(200, 100),
          viewportSize: viewport,
        ),
        const Offset(600, 500),
      );
    });

    test('does not go past the top-left, including padding', () {
      expect(
        fitMenuToViewport(
          preferred: const Offset(-20, -10),
          menuSize: const Size(200, 100),
          viewportSize: viewport,
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        ),
        const Offset(8, 12),
      );
    });
  });

  group('fitSubmenuToViewport', () {
    test('opens to the right of the parent item when it fits', () {
      expect(
        fitSubmenuToViewport(
          anchor: const Rect.fromLTWH(100, 80, 180, 32),
          menuSize: const Size(160, 90),
          viewportSize: viewport,
        ),
        const Offset(280, 80),
      );
    });

    test('opens to the left of the parent item when the right side overflows',
        () {
      expect(
        fitSubmenuToViewport(
          anchor: const Rect.fromLTWH(650, 80, 140, 32),
          menuSize: const Size(160, 90),
          viewportSize: viewport,
        ),
        const Offset(490, 80),
      );
    });

    test('shifts up when the submenu would overflow the bottom', () {
      final origin = fitSubmenuToViewport(
        anchor: const Rect.fromLTWH(100, 540, 180, 32),
        menuSize: const Size(160, 90),
        viewportSize: viewport,
      );
      expect(origin.dx, 280);
      expect(origin.dy, 510);
    });
  });
}
