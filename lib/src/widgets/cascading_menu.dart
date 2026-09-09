import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/file_tile_colors.dart';
import '../utils/menu_position.dart';

typedef MenuItemCallback = FutureOr<void> Function();
typedef BarrierTapCallback = void Function(Offset position);

class CascadingMenuItem {
  final String label;
  final IconData? icon;
  final MenuItemCallback? onTap;
  final List<CascadingMenuItem>? children;
  final Color? textColor;
  final Color? iconColor;
  final bool isDivider;
  final bool flashConfirm;

  CascadingMenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.children,
    this.textColor,
    this.iconColor,
    this.isDivider = false,
    this.flashConfirm = false,
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
  final bool Function(PointerDownEvent event)? isSelectionBoxGesture;

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
    this.isSelectionBoxGesture,
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
    bool Function(PointerDownEvent event)? isSelectionBoxGesture,
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
        isSelectionBoxGesture: isSelectionBoxGesture,
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
    final startSelectionBox = widget.isSelectionBoxGesture?.call(event) ??
        (event.buttons & kPrimaryButton != 0 &&
            HardwareKeyboard.instance.isShiftPressed);
    if (startSelectionBox) {
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
    return SizedBox.expand(
      child: Stack(
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
            CustomSingleChildLayout(
              delegate: _MenuLayoutDelegate(
                preferred: widget.position,
                padding: MediaQuery.paddingOf(context),
              ),
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
      ),
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
  final List<GlobalKey> _itemKeys = [];
  int? _confirmedIndex;
  Timer? _confirmTimer;

  @override
  void dispose() {
    _submenuOverlay?.remove();
    _hideSubmenuTimer?.cancel();
    _confirmTimer?.cancel();
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
    final anchor = Rect.fromLTWH(
      itemPosition.dx,
      itemPosition.dy,
      renderBox.size.width,
      renderBox.size.height,
    );

    _submenuOverlay = OverlayEntry(
      builder: (overlayContext) => SizedBox.expand(
        child: CustomSingleChildLayout(
          delegate: _SubmenuLayoutDelegate(
            anchor: anchor,
            padding: MediaQuery.paddingOf(overlayContext),
          ),
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
      ),
    );

    _submenuForIndex = index;
    Overlay.of(context).insert(_submenuOverlay!);
  }

  void _scheduleHideSubmenu() {
    _hideSubmenuTimer?.cancel();
    _hideSubmenuTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted &&
          (_hoveredIndex == null || _hoveredIndex != _submenuForIndex) &&
          !_submenuHovered) {
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
    final colors = Theme.of(context).extension<FileTileColors>()!;
    final backgroundColor = widget.backgroundColor ?? colors.surface;

    while (_itemKeys.length < widget.items.length) {
      _itemKeys.add(GlobalKey());
    }

    final items = Column(
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

          final itemKey = _itemKeys[index];
          final isHovered = _hoveredIndex == index;
          final hasChildren =
              item.children != null && item.children!.isNotEmpty;
          final confirmed = _confirmedIndex == index;

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
                if (mounted && _hoveredIndex == index) {
                  setState(() => _hoveredIndex = null);
                }
              });
            },
            child: GestureDetector(
              key: itemKey,
              behavior: HitTestBehavior.opaque,
              onTap: item.onTap != null
                  ? () async {
                      try {
                        await item.onTap!();
                      } catch (_) {
                        return;
                      }
                      if (!item.flashConfirm || !mounted) return;
                      _confirmTimer?.cancel();
                      setState(() => _confirmedIndex = index);
                      _confirmTimer = Timer(
                        const Duration(milliseconds: 800),
                        () {
                          if (mounted) {
                            setState(() => _confirmedIndex = null);
                          }
                        },
                      );
                    }
                  : null,
              child: Container(
                color: isHovered ? colors.overlayHover : Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        confirmed ? Icons.check : item.icon,
                        color: confirmed
                            ? colors.accent
                            : item.iconColor ?? colors.textSecondary,
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget body = items;
        if (constraints.hasBoundedHeight) {
          body = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: SingleChildScrollView(child: items),
          );
        }
        return Material(
          color: Colors.transparent,
          child: IntrinsicWidth(
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border.all(color: colors.borderSubtle, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: body,
            ),
          ),
        );
      },
    );
  }
}

class _MenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset preferred;
  final EdgeInsets padding;

  _MenuLayoutDelegate({required this.preferred, required this.padding});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0.0, constraints.maxWidth - padding.horizontal),
      maxHeight: math.max(0.0, constraints.maxHeight - padding.vertical),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return fitMenuToViewport(
      preferred: preferred,
      menuSize: childSize,
      viewportSize: size,
      padding: padding,
    );
  }

  @override
  bool shouldRelayout(_MenuLayoutDelegate oldDelegate) {
    return preferred != oldDelegate.preferred || padding != oldDelegate.padding;
  }
}

class _SubmenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect anchor;
  final EdgeInsets padding;

  _SubmenuLayoutDelegate({required this.anchor, required this.padding});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0.0, constraints.maxWidth - padding.horizontal),
      maxHeight: math.max(0.0, constraints.maxHeight - padding.vertical),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return fitSubmenuToViewport(
      anchor: anchor,
      menuSize: childSize,
      viewportSize: size,
      padding: padding,
    );
  }

  @override
  bool shouldRelayout(_SubmenuLayoutDelegate oldDelegate) {
    return anchor != oldDelegate.anchor || padding != oldDelegate.padding;
  }
}
