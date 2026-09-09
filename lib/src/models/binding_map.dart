import 'package:flutter/services.dart';

import 'click_event.dart';

/// Remappable named actions. Mouse input is a closed set of [PointerChord]s,
/// not free-form mouse programming.
enum ControlAction {
  selectSingle,
  toggleSelect,
  rangeSelect,
  selectionBox,
  delete,
  copy,
  cut,
  paste,
  zoom,
  panVertical,
  panHorizontal,
}

enum PointerChord {
  primaryClick,
  ctrlPrimaryClick,
  shiftPrimaryClick,
  altPrimaryClick,
  metaPrimaryClick,
  ctrlShiftPrimaryClick,
  primaryDrag,
  ctrlPrimaryDrag,
  shiftPrimaryDrag,
  altPrimaryDrag,
  scroll,
  ctrlScroll,
  shiftScroll,
  altScroll,
}

enum _PointerFamily { click, drag, scroll }

extension PointerChordX on PointerChord {
  _PointerFamily get family {
    switch (this) {
      case PointerChord.primaryClick:
      case PointerChord.ctrlPrimaryClick:
      case PointerChord.shiftPrimaryClick:
      case PointerChord.altPrimaryClick:
      case PointerChord.metaPrimaryClick:
      case PointerChord.ctrlShiftPrimaryClick:
        return _PointerFamily.click;
      case PointerChord.primaryDrag:
      case PointerChord.ctrlPrimaryDrag:
      case PointerChord.shiftPrimaryDrag:
      case PointerChord.altPrimaryDrag:
        return _PointerFamily.drag;
      case PointerChord.scroll:
      case PointerChord.ctrlScroll:
      case PointerChord.shiftScroll:
      case PointerChord.altScroll:
        return _PointerFamily.scroll;
    }
  }

  ClickModifiers get modifiers {
    switch (this) {
      case PointerChord.primaryClick:
      case PointerChord.primaryDrag:
      case PointerChord.scroll:
        return const ClickModifiers();
      case PointerChord.ctrlPrimaryClick:
      case PointerChord.ctrlPrimaryDrag:
      case PointerChord.ctrlScroll:
        return const ClickModifiers(ctrl: true);
      case PointerChord.shiftPrimaryClick:
      case PointerChord.shiftPrimaryDrag:
      case PointerChord.shiftScroll:
        return const ClickModifiers(shift: true);
      case PointerChord.altPrimaryClick:
      case PointerChord.altPrimaryDrag:
      case PointerChord.altScroll:
        return const ClickModifiers(alt: true);
      case PointerChord.metaPrimaryClick:
        return const ClickModifiers(meta: true);
      case PointerChord.ctrlShiftPrimaryClick:
        return const ClickModifiers(ctrl: true, shift: true);
    }
  }

  String get label {
    switch (this) {
      case PointerChord.primaryClick:
        return 'Left Click';
      case PointerChord.ctrlPrimaryClick:
        return 'Ctrl + Click';
      case PointerChord.shiftPrimaryClick:
        return 'Shift + Click';
      case PointerChord.altPrimaryClick:
        return 'Alt + Click';
      case PointerChord.metaPrimaryClick:
        return 'Cmd + Click';
      case PointerChord.ctrlShiftPrimaryClick:
        return 'Ctrl + Shift + Click';
      case PointerChord.primaryDrag:
        return 'Left Drag';
      case PointerChord.ctrlPrimaryDrag:
        return 'Ctrl + Drag';
      case PointerChord.shiftPrimaryDrag:
        return 'Shift + Drag';
      case PointerChord.altPrimaryDrag:
        return 'Alt + Drag';
      case PointerChord.scroll:
        return 'Scroll';
      case PointerChord.ctrlScroll:
        return 'Ctrl + Scroll';
      case PointerChord.shiftScroll:
        return 'Shift + Scroll';
      case PointerChord.altScroll:
        return 'Alt + Scroll';
    }
  }
}

class KeyChord {
  final int logicalKeyId;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  /// When true, Control (Linux/Windows) or Meta (macOS) satisfies the shortcut
  /// modifier. [ctrl] and [meta] are ignored for matching.
  final bool shortcut;

  const KeyChord({
    required this.logicalKeyId,
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
    this.shortcut = false,
  });

  factory KeyChord.fromKeyEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final hasShortcut = keyboard.isControlPressed || keyboard.isMetaPressed;
    return KeyChord(
      logicalKeyId: event.logicalKey.keyId,
      shortcut: hasShortcut,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    );
  }

  factory KeyChord.fromJson(Map<String, dynamic> json) {
    return KeyChord(
      logicalKeyId: (json['logicalKeyId'] as num).toInt(),
      ctrl: json['ctrl'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
      shortcut: json['shortcut'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'logicalKeyId': logicalKeyId,
        'ctrl': ctrl,
        'shift': shift,
        'alt': alt,
        'meta': meta,
        'shortcut': shortcut,
      };

  LogicalKeyboardKey get logicalKey =>
      LogicalKeyboardKey.findKeyByKeyId(logicalKeyId) ??
      LogicalKeyboardKey.unidentified;

  bool get isModifierOnly {
    final key = logicalKey;
    return key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  bool matches(LogicalKeyboardKey key, {required ClickModifiers modifiers}) {
    if (key.keyId != logicalKeyId) return false;
    if (shift != modifiers.shift || alt != modifiers.alt) return false;
    if (shortcut) {
      return modifiers.ctrl || modifiers.meta;
    }
    return ctrl == modifiers.ctrl && meta == modifiers.meta;
  }

  String get label {
    final key = logicalKey;
    final name = key.keyLabel.isNotEmpty
        ? key.keyLabel.toUpperCase()
        : (key.debugName ?? 'Key');
    final parts = <String>[];
    if (shortcut) {
      parts.add('Ctrl/Cmd');
    } else {
      if (ctrl) parts.add('Ctrl');
      if (meta) parts.add('Cmd');
    }
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    parts.add(name);
    return parts.join(' + ');
  }

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      logicalKeyId == other.logicalKeyId &&
      ctrl == other.ctrl &&
      shift == other.shift &&
      alt == other.alt &&
      meta == other.meta &&
      shortcut == other.shortcut;

  @override
  int get hashCode =>
      Object.hash(logicalKeyId, ctrl, shift, alt, meta, shortcut);
}

class ControlBinding {
  final PointerChord? pointer;
  final KeyChord? key;

  const ControlBinding.pointer(PointerChord this.pointer) : key = null;

  const ControlBinding.key(KeyChord this.key) : pointer = null;

  bool get isPointer => pointer != null;
  bool get isKey => key != null;

  factory ControlBinding.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'key') {
      return ControlBinding.key(
          KeyChord.fromJson(Map<String, dynamic>.from(json)));
    }
    final chordName = json['chord'] as String?;
    final chord = PointerChord.values.asNameMap()[chordName];
    if (chord == null) {
      throw FormatException('Unknown pointer chord: $chordName');
    }
    return ControlBinding.pointer(chord);
  }

  Map<String, dynamic> toJson() {
    if (key != null) {
      return {'type': 'key', ...key!.toJson()};
    }
    return {'type': 'pointer', 'chord': pointer!.name};
  }

  String get label => key?.label ?? pointer?.label ?? '';

  bool conflictsWith(ControlBinding other) {
    if (pointer != null && other.pointer != null) {
      return pointer == other.pointer;
    }
    if (key != null && other.key != null) {
      return key == other.key;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is ControlBinding && pointer == other.pointer && key == other.key;

  @override
  int get hashCode => Object.hash(pointer, key);
}

class BindingMap {
  final Map<ControlAction, ControlBinding> _bindings;

  BindingMap(Map<ControlAction, ControlBinding> bindings)
      : _bindings = Map.unmodifiable(Map.of(bindings));

  ControlBinding operator [](ControlAction action) =>
      _bindings[action] ?? defaults[action];

  Iterable<ControlAction> get actions => ControlAction.values;

  static final BindingMap defaults = BindingMap({
    ControlAction.selectSingle:
        const ControlBinding.pointer(PointerChord.primaryClick),
    ControlAction.toggleSelect:
        const ControlBinding.pointer(PointerChord.ctrlPrimaryClick),
    ControlAction.rangeSelect:
        const ControlBinding.pointer(PointerChord.shiftPrimaryClick),
    ControlAction.selectionBox:
        const ControlBinding.pointer(PointerChord.shiftPrimaryDrag),
    ControlAction.delete: ControlBinding.key(
      KeyChord(logicalKeyId: LogicalKeyboardKey.delete.keyId),
    ),
    ControlAction.copy: ControlBinding.key(
      KeyChord(
        logicalKeyId: LogicalKeyboardKey.keyC.keyId,
        shortcut: true,
      ),
    ),
    ControlAction.cut: ControlBinding.key(
      KeyChord(
        logicalKeyId: LogicalKeyboardKey.keyX.keyId,
        shortcut: true,
      ),
    ),
    ControlAction.paste: ControlBinding.key(
      KeyChord(
        logicalKeyId: LogicalKeyboardKey.keyV.keyId,
        shortcut: true,
      ),
    ),
    ControlAction.zoom: const ControlBinding.pointer(PointerChord.scroll),
    ControlAction.panVertical:
        const ControlBinding.pointer(PointerChord.shiftScroll),
    ControlAction.panHorizontal:
        const ControlBinding.pointer(PointerChord.ctrlScroll),
  });

  factory BindingMap.fromJson(Object? json) {
    final merged = Map<ControlAction, ControlBinding>.from(defaults._bindings);
    if (json is Map) {
      json.forEach((key, value) {
        if (value is! Map) return;
        final action = ControlAction.values.asNameMap()[key.toString()];
        if (action == null) return;
        try {
          merged[action] =
              ControlBinding.fromJson(Map<String, dynamic>.from(value));
        } catch (_) {}
      });
    }
    return BindingMap(merged);
  }

  Map<String, dynamic> toJson() => {
        for (final action in ControlAction.values)
          action.name: this[action].toJson(),
      };

  /// Assign [binding] to [action]. If another action already uses that chord,
  /// the two swap so the map stays conflict-free.
  BindingMap rebind(ControlAction action, ControlBinding binding) {
    final next = Map<ControlAction, ControlBinding>.from(_bindings);
    final previous = next[action] ?? defaults[action];
    ControlAction? occupant;
    for (final other in ControlAction.values) {
      if (other == action) continue;
      if ((next[other] ?? defaults[other]).conflictsWith(binding)) {
        occupant = other;
        break;
      }
    }
    next[action] = binding;
    if (occupant != null) {
      next[occupant] = previous;
    }
    return BindingMap(next);
  }

  ControlAction? conflictFor(ControlAction action, ControlBinding binding) {
    for (final other in ControlAction.values) {
      if (other == action) continue;
      if (this[other].conflictsWith(binding)) return other;
    }
    return null;
  }

  ClickAction resolveClick(ClickModifiers modifiers) {
    final chord = pointerChordFor(modifiers, _PointerFamily.click);
    if (chord == null) return ClickAction.noOp;
    for (final action in const [
      ControlAction.selectSingle,
      ControlAction.toggleSelect,
      ControlAction.rangeSelect,
    ]) {
      if (this[action].pointer == chord) {
        return switch (action) {
          ControlAction.selectSingle => ClickAction.selectSingle,
          ControlAction.toggleSelect => ClickAction.toggleSelect,
          ControlAction.rangeSelect => ClickAction.rangeSelect,
          _ => ClickAction.noOp,
        };
      }
    }
    return ClickAction.noOp;
  }

  ControlAction? resolveScroll(ClickModifiers modifiers) {
    final chord = pointerChordFor(modifiers, _PointerFamily.scroll);
    if (chord == null) return null;
    for (final action in const [
      ControlAction.zoom,
      ControlAction.panVertical,
      ControlAction.panHorizontal,
    ]) {
      if (this[action].pointer == chord) return action;
    }
    return null;
  }

  bool isSelectionBoxModifiers(ClickModifiers modifiers) {
    final bound = this[ControlAction.selectionBox].pointer;
    if (bound == null || bound.family != _PointerFamily.drag) return false;
    return bound.modifiers == modifiers;
  }

  ControlAction? resolveKey(LogicalKeyboardKey key, ClickModifiers modifiers) {
    for (final action in const [
      ControlAction.delete,
      ControlAction.copy,
      ControlAction.cut,
      ControlAction.paste,
    ]) {
      final chord = this[action].key;
      if (chord != null && chord.matches(key, modifiers: modifiers)) {
        return action;
      }
    }
    return null;
  }

  static PointerChord? pointerChordFor(
      ClickModifiers modifiers, _PointerFamily family) {
    for (final chord in PointerChord.values) {
      if (chord.family == family && chord.modifiers == modifiers) {
        return chord;
      }
    }
    return null;
  }

  List<PointerChord> chordsFor(ControlAction action) {
    switch (action) {
      case ControlAction.selectSingle:
      case ControlAction.toggleSelect:
      case ControlAction.rangeSelect:
        return PointerChord.values
            .where((c) => c.family == _PointerFamily.click)
            .toList();
      case ControlAction.selectionBox:
        return PointerChord.values
            .where((c) => c.family == _PointerFamily.drag)
            .toList();
      case ControlAction.zoom:
      case ControlAction.panVertical:
      case ControlAction.panHorizontal:
        return PointerChord.values
            .where((c) => c.family == _PointerFamily.scroll)
            .toList();
      case ControlAction.delete:
      case ControlAction.copy:
      case ControlAction.cut:
      case ControlAction.paste:
        return const [];
    }
  }

  String labelOf(ControlAction action) {
    switch (action) {
      case ControlAction.selectSingle:
        return 'Select single';
      case ControlAction.toggleSelect:
        return 'Toggle select';
      case ControlAction.rangeSelect:
        return 'Range select';
      case ControlAction.selectionBox:
        return 'Selection box';
      case ControlAction.delete:
        return 'Delete selected';
      case ControlAction.copy:
        return 'Copy';
      case ControlAction.cut:
        return 'Cut';
      case ControlAction.paste:
        return 'Paste';
      case ControlAction.zoom:
        return 'Zoom';
      case ControlAction.panVertical:
        return 'Vertical pan';
      case ControlAction.panHorizontal:
        return 'Horizontal pan';
    }
  }
}
