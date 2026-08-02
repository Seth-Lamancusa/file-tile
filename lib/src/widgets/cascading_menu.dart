import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/stitch_colors.dart';

typedef MenuItemCallback = void Function();
typedef BarrierTapCallback = void Function(Offset position);

class CascadingMenuItem {
  final String label;
  final IconData? icon;
  final MenuItemCallback? onTap;
  final List<CascadingMenuItem>? children;
  final Color? textColor;
  final Color? iconColor;
  final bool isDivider;

  CascadingMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.children,
    this.textColor,
    this.iconColor,
    this.isDivider = false,
  });

  static CascadingMenuItem divider() => CascadingMenuItem(
    label: '',
    isDivider: true,
  );
}

class CascadingMenu extends StatefulWidget {
  final Offset position;
  final List<CascadingMenuItem> items;
  final Color? backgroundColor;
  final VoidCallback? onClose;
  final BarrierTapCallback? onBarrierLeftTapped;
  final BarrierTapCallback? onBarrierRightTapped;
  final ValueChanged<Offset>? onBarrierShiftDragStart;
  final ValueChanged<Offset>? onBarrierShiftDragUpdate;
  final VoidCallback? onBarrierShiftDragEnd;

  const CascadingMenu({
    super.key,
    required this.position,
    required this.items,
    this.backgroundColor,
    this.onClose,
    this.onBarrierLeftTapped,
    this.onBarrierRightTapped,
    this.onBarrierShiftDragStart,
    this.onBarrierShiftDragUpdate,
    this.onBarrierShiftDragEnd,
  });

  static void show(
    BuildContext context, {
    required Offset position,
    required List<CascadingMenuItem> items,
    Color? backgroundColor,
    VoidCallback? onClose,
    BarrierTapCallback? onBarrierLeftTapped,
    BarrierTapCallback? onBarrierRightTapped,
    ValueChanged<Offset>? onBarrierShiftDragStart,
    ValueChanged<Offset>? onBarrierShiftDragUpdate,
    VoidCallback? onBarrierShiftDragEnd,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss menu',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, __) => CascadingMenu(
        position: position,
        items: items,
        backgroundColor: backgroundColor,
        onClose: onClose,
        onBarrierLeftTapped: onBarrierLeftTapped,
        onBarrierRightTapped: onBarrierRightTapped,
        onBarrierShiftDragStart: onBarrierShiftDragStart,
        onBarrierShiftDragUpdate: onBarrierShiftDragUpdate,
        onBarrierShiftDragEnd: onBarrierShiftDragEnd,
      ),
    );
  }

  @override
  State<CascadingMenu> createState() => _CascadingMenuState();
}

class _CascadingMenuState extends State<CascadingMenu> {
  bool _shiftDragActive = false;
  bool _hideMenu = false;

  void _handleBarrierPointerDown(PointerDownEvent event) {
    // Shift+drag should close the menu and start a selection box, but the
    // drag gesture began on this barrier - keep the barrier mounted so we
    // keep receiving the move/up events for this pointer, and pop only once
    // the drag completes (mirrors normal selection-box behavior).
    if (event.buttons & kPrimaryButton != 0 && HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        _shiftDragActive = true;
        _hideMenu = true;
      });
      widget.onBarrierShiftDragStart?.call(event.position);
      return;
    }

    Navigator.pop(context);
    widget.onClose?.call();

    if (event.buttons & kPrimaryButton != 0) {
      widget.onBarrierLeftTapped?.call(event.position);
    } else if (event.buttons & kSecondaryButton != 0) {
      widget.onBarrierRightTapped?.call(event.position);
    }
  }

  void _handleBarrierPointerMove(PointerMoveEvent event) {
    if (_shiftDragActive) {
      widget.onBarrierShiftDragUpdate?.call(event.position);
    }
  }

  void _endShiftDrag() {
    _shiftDragActive = false;
    widget.onBarrierShiftDragEnd?.call();
    Navigator.pop(context);
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: _handleBarrierPointerDown,
            onPointerMove: _handleBarrierPointerMove,
            onPointerUp: (_) {
              if (_shiftDragActive) _endShiftDrag();
            },
            onPointerCancel: (_) {
              if (_shiftDragActive) _endShiftDrag();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(),
          ),
        ),
        if (!_hideMenu)
          Positioned(
            left: widget.position.dx,
            top: widget.position.dy,
            child: _MenuPanel(
              items: widget.items,
              backgroundColor: widget.backgroundColor,
              onClose: () {
                Navigator.pop(context);
                widget.onClose?.call();
              },
            ),
          ),
      ],
    );
  }
}

class _MenuPanel extends StatefulWidget {
  final List<CascadingMenuItem> items;
  final Color? backgroundColor;
  final VoidCallback onClose;

  const _MenuPanel({
    required this.items,
    required this.backgroundColor,
    required this.onClose,
  });

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  int? _hoveredIndex;
  int? _submenuForIndex;
  OverlayEntry? _submenuOverlay;
  Timer? _hideSubmenuTimer;
  bool _submenuHovered = false;

  @override
  void dispose() {
    _submenuOverlay?.remove();
    _hideSubmenuTimer?.cancel();
    super.dispose();
  }

  void _showSubmenu(int index, GlobalKey itemKey) {
    _hideSubmenuTimer?.cancel();
    _submenuHovered = false;
    _submenuOverlay?.remove();

    final item = widget.items[index];
    if (item.children == null || item.children!.isEmpty) return;

    final renderBox = itemKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final itemPosition = renderBox.localToGlobal(Offset.zero);

    _submenuOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            left: itemPosition.dx + renderBox.size.width,
            top: itemPosition.dy,
            child: MouseRegion(
              onEnter: (_) {
                _hideSubmenuTimer?.cancel();
                _submenuHovered = true;
              },
              onExit: (_) {
                _submenuHovered = false;
                if (_hoveredIndex == null || _hoveredIndex != _submenuForIndex) {
                  _scheduleHideSubmenu();
                }
              },
              child: _MenuPanel(
                items: item.children!,
                backgroundColor: widget.backgroundColor,
                onClose: widget.onClose,
              ),
            ),
          ),
        ],
      ),
    );

    _submenuForIndex = index;
    Overlay.of(context).insert(_submenuOverlay!);
  }

  void _scheduleHideSubmenu() {
    _hideSubmenuTimer?.cancel();
    _hideSubmenuTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted && (_hoveredIndex == null || _hoveredIndex != _submenuForIndex) && !_submenuHovered) {
        _submenuOverlay?.remove();
        _submenuOverlay = null;
        _submenuForIndex = null;
      }
    });
  }

  void _hideSubmenuImmediately() {
    _hideSubmenuTimer?.cancel();
    _submenuOverlay?.remove();
    _submenuOverlay = null;
    _submenuForIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<StitchColors>()!;
    final backgroundColor = widget.backgroundColor ?? colors.surface;

    return Material(
      color: Colors.transparent,
      child: IntrinsicWidth(
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: colors.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(
            widget.items.length,
            (index) {
              final item = widget.items[index];
              if (item.isDivider) {
                return Divider(
                  height: 1,
                  color: colors.borderSubtle,
                );
              }

              final itemKey = GlobalKey();
              final isHovered = _hoveredIndex == index;
              final hasChildren = item.children != null && item.children!.isNotEmpty;

              return MouseRegion(
                onEnter: (_) {
                  _hideSubmenuTimer?.cancel();
                  setState(() => _hoveredIndex = index);

                  if (_submenuForIndex != null && _submenuForIndex != index) {
                    _hideSubmenuImmediately();
                  }

                  if (hasChildren) {
                    _showSubmenu(index, itemKey);
                  }
                },
                onExit: (_) {
                  if (hasChildren) {
                    _scheduleHideSubmenu();
                  } else {
                    _hideSubmenuImmediately();
                  }
                  Future.microtask(() {
                    if (mounted) {
                      setState(() => _hoveredIndex = null);
                    }
                  });
                },
                child: GestureDetector(
                  key: itemKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: item.onTap != null
                    ? () {
                        item.onTap!();
                      }
                    : null,
                  child: Container(
                    color: isHovered
                      ? colors.overlayHover
                      : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (item.icon != null) ...[
                          Icon(
                            item.icon,
                            color: item.iconColor ?? colors.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          item.label,
                          style: TextStyle(
                            color: item.textColor ?? colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        if (hasChildren) ...[
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            color: colors.textDim,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}
