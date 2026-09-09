import 'package:file_tile/src/models/binding_map.dart';
import 'package:file_tile/src/models/click_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults match current click / scroll / key behavior', () {
    final map = BindingMap.defaults;
    expect(
      map.resolveClick(const ClickModifiers()),
      ClickAction.selectSingle,
    );
    expect(
      map.resolveClick(const ClickModifiers(ctrl: true)),
      ClickAction.toggleSelect,
    );
    expect(
      map.resolveClick(const ClickModifiers(shift: true)),
      ClickAction.rangeSelect,
    );
    expect(
      map.resolveClick(const ClickModifiers(ctrl: true, shift: true)),
      ClickAction.noOp,
    );
    expect(map.resolveScroll(const ClickModifiers()), ControlAction.zoom);
    expect(
      map.resolveScroll(const ClickModifiers(shift: true)),
      ControlAction.panVertical,
    );
    expect(
      map.resolveScroll(const ClickModifiers(ctrl: true)),
      ControlAction.panHorizontal,
    );
    expect(
        map.isSelectionBoxModifiers(const ClickModifiers(shift: true)), isTrue);
    expect(map.isSelectionBoxModifiers(const ClickModifiers()), isFalse);
  });

  test('rebind swaps when the chord is already used', () {
    final swapped = BindingMap.defaults.rebind(
      ControlAction.toggleSelect,
      const ControlBinding.pointer(PointerChord.shiftPrimaryClick),
    );
    expect(
      swapped[ControlAction.toggleSelect].pointer,
      PointerChord.shiftPrimaryClick,
    );
    expect(
      swapped[ControlAction.rangeSelect].pointer,
      PointerChord.ctrlPrimaryClick,
    );
    expect(
      swapped.resolveClick(const ClickModifiers(shift: true)),
      ClickAction.toggleSelect,
    );
  });

  test('fromJson merges over defaults and ignores unknown keys', () {
    final map = BindingMap.fromJson({
      'zoom': {'type': 'pointer', 'chord': 'ctrlScroll'},
      'panHorizontal': {'type': 'pointer', 'chord': 'scroll'},
      'notAnAction': {'type': 'pointer', 'chord': 'scroll'},
    });
    expect(map[ControlAction.zoom].pointer, PointerChord.ctrlScroll);
    expect(map[ControlAction.panHorizontal].pointer, PointerChord.scroll);
    expect(map[ControlAction.selectSingle].pointer, PointerChord.primaryClick);
  });

  test('copy shortcut matches ctrl or meta plus C', () {
    final map = BindingMap.defaults;
    expect(
      map.resolveKey(LogicalKeyboardKey.keyC, const ClickModifiers(ctrl: true)),
      ControlAction.copy,
    );
    expect(
      map.resolveKey(LogicalKeyboardKey.keyC, const ClickModifiers(meta: true)),
      ControlAction.copy,
    );
    expect(
      map.resolveKey(LogicalKeyboardKey.keyC, const ClickModifiers()),
      isNull,
    );
  });

  test('round-trips through JSON', () {
    final original = BindingMap.defaults.rebind(
      ControlAction.delete,
      ControlBinding.key(
        KeyChord(
          logicalKeyId: LogicalKeyboardKey.backspace.keyId,
        ),
      ),
    );
    final restored = BindingMap.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
    expect(
      restored[ControlAction.delete].key!.logicalKeyId,
      LogicalKeyboardKey.backspace.keyId,
    );
  });
}
