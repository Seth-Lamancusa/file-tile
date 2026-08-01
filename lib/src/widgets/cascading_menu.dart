import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
  final Color backgroundColor;
  final VoidCallback? onClose;
  final BarrierTapCallback? onBarrierLeftTapped;
  final BarrierTapCallback? onBarrierRightTapped;

  const CascadingMenu({
    super.key,
    required this.position,
    required this.items,
    this.backgroundColor = const Color(0xFF1E1E1E),
    this.onClose,
    this.onBarrierLeftTapped,
    this.onBarrierRightTapped,
  });

  static void show(
    BuildContext context, {
    required Offset position,
    required List<CascadingMenuItem> items,
    Color backgroundColor = const Color(0xFF1E1E1E),
    VoidCallback? onClose,
    BarrierTapCallback? onBarrierLeftTapped,
    BarrierTapCallback? onBarrierRightTapped,
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
      ),
    );
  }

  @override
  State<CascadingMenu> createState() => _CascadingMenuState();
}

class _CascadingMenuState extends State<CascadingMenu> {
  void _handleBarrierPointerDown(PointerDownEvent event) {
    Navigator.pop(context);
    widget.onClose?.call();

    if (event.buttons & kPrimaryButton != 0) {
      widget.onBarrierLeftTapped?.call(event.position);
    } else if (event.buttons & kSecondaryButton != 0) {
      widget.onBarrierRightTapped?.call(event.position);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: _handleBarrierPointerDown,
            behavior: HitTestBehavior.opaque,
            child: Container(),
          ),
        ),
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
  final Color backgroundColor;
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
    return Material(
      color: Colors.transparent,
      child: IntrinsicWidth(
        child: Container(
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            border: Border.all(color: Colors.white12, width: 1),
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
                  color: Colors.white12,
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
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (item.icon != null) ...[
                          Icon(
                            item.icon,
                            color: item.iconColor ?? Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          item.label,
                          style: TextStyle(
                            color: item.textColor ?? Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        if (hasChildren) ...[
                          const Spacer(),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.white54,
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
