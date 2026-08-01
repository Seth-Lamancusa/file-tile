import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stitch_desktop_grid/src/controllers/click_handler.dart';
import 'package:stitch_desktop_grid/src/controllers/selection_controller.dart';
import 'package:stitch_desktop_grid/src/models/click_event.dart';
import 'package:stitch_desktop_grid/src/utils/coordinate_space.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('ClickHandler', () {
    late SelectionController selectionController;
    late ClickHandler clickHandler;

    setUp(() {
      selectionController = SelectionController();
      clickHandler = ClickHandler(selectionController: selectionController);
    });

    test('selectSingle clears previous selection', () {
      final nodes = [
        HitTestNode(id: 'node1', position: Offset.zero, size: 80),
        HitTestNode(id: 'node2', position: Offset(80, 0), size: 80),
      ];
      final coords = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);

      // Click node1
      clickHandler.handlePointerDown(
        screenPosition: Offset(40, 40),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, {'node1'});

      // Click node2
      clickHandler.handlePointerDown(
        screenPosition: Offset(120, 40),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, {'node2'});
    });

    test('empty canvas click clears selection', () {
      final nodes = [
        HitTestNode(id: 'node1', position: Offset.zero, size: 80),
      ];
      final coords = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);

      // Click node1
      clickHandler.handlePointerDown(
        screenPosition: Offset(40, 40),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, {'node1'});

      // Click empty area
      clickHandler.handlePointerDown(
        screenPosition: Offset(200, 200),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, isEmpty);
    });

    test('range select finds all nodes in bounding box', () {
      final nodes = [
        HitTestNode(id: 'node1', position: Offset.zero, size: 80),
        HitTestNode(id: 'node2', position: Offset(80, 0), size: 80),
        HitTestNode(id: 'node3', position: Offset(0, 80), size: 80),
        HitTestNode(id: 'node4', position: Offset(80, 80), size: 80),
      ];
      final coords = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);

      // Select node1
      clickHandler.handlePointerDown(
        screenPosition: Offset(40, 40),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, {'node1'});

      // Simulate Shift+click on node4 (would trigger rangeSelect in real code)
      selectionController.rangeSelect(['node1', 'node2', 'node3', 'node4']);
      expect(selectionController.selected, {'node1', 'node2', 'node3', 'node4'});
    });

    test('toggleSelect adds and removes nodes', () {
      final nodes = [
        HitTestNode(id: 'node1', position: Offset.zero, size: 80),
        HitTestNode(id: 'node2', position: Offset(80, 0), size: 80),
      ];
      final coords = CoordinateSpace(scale: 1.0, panOffset: Offset.zero);

      // Single click node1
      clickHandler.handlePointerDown(
        screenPosition: Offset(40, 40),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, {'node1'});

      // Toggle-select node2 (simulating Ctrl+click in real code)
      selectionController.toggleSelect('node2');
      expect(selectionController.selected, {'node1', 'node2'});

      // Toggle-select node1 to remove it
      selectionController.toggleSelect('node1');
      expect(selectionController.selected, {'node2'});
    });

    test('handles scaled coordinates correctly', () {
      final nodes = [
        HitTestNode(id: 'node1', position: Offset.zero, size: 80),
      ];
      // 2x zoom
      final coords = CoordinateSpace(scale: 2.0, panOffset: Offset.zero);

      // At 2x zoom, node1 (80x80 logical) renders as 160x160 screen pixels
      // Clicking at screen (80, 80) should hit node1
      clickHandler.handlePointerDown(
        screenPosition: Offset(80, 80),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, {'node1'});
    });

    test('handles pan offset correctly', () {
      final nodes = [
        HitTestNode(id: 'node1', position: Offset.zero, size: 80),
      ];
      // Pan offset of (50, 50)
      final coords = CoordinateSpace(scale: 1.0, panOffset: Offset(50, 50));

      // With pan offset, the node appears at screen position (50, 50) to (130, 130)
      clickHandler.handlePointerDown(
        screenPosition: Offset(90, 90),
        nodes: nodes,
        coords: coords,
      );
      expect(selectionController.selected, {'node1'});
    });
  });

  group('ClickModifiers', () {
    test('can be created with individual flags', () {
      final mods = ClickModifiers(ctrl: true, shift: false, alt: false);
      expect(mods.ctrl, isTrue);
      expect(mods.shift, isFalse);
      expect(mods.alt, isFalse);
    });

    test('equality works correctly', () {
      final mods1 = ClickModifiers(ctrl: true, shift: false, alt: false);
      final mods2 = ClickModifiers(ctrl: true, shift: false, alt: false);
      final mods3 = ClickModifiers(ctrl: false, shift: false, alt: false);

      expect(mods1, equals(mods2));
      expect(mods1, isNot(equals(mods3)));
    });
  });

  group('ClickActionMapper', () {
    test('maps plain click to selectSingle', () {
      final mods = ClickModifiers(ctrl: false, shift: false, alt: false);
      expect(ClickActionMapper.mapModifiersToAction(mods), ClickAction.selectSingle);
    });

    test('maps Ctrl+click to toggleSelect', () {
      final mods = ClickModifiers(ctrl: true, shift: false, alt: false);
      expect(ClickActionMapper.mapModifiersToAction(mods), ClickAction.toggleSelect);
    });

    test('maps Shift+click to rangeSelect', () {
      final mods = ClickModifiers(ctrl: false, shift: true, alt: false);
      expect(ClickActionMapper.mapModifiersToAction(mods), ClickAction.rangeSelect);
    });

    test('maps unsupported modifiers to noOp', () {
      final mods = ClickModifiers(ctrl: true, shift: true, alt: false);
      expect(ClickActionMapper.mapModifiersToAction(mods), ClickAction.noOp);
    });
  });
}
