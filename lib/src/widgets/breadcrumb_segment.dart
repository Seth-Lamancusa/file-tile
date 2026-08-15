import 'package:flutter/material.dart';

import '../theme/file_tile_colors.dart';

class BreadcrumbSegment extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLast;
  final bool isDragTarget;

  const BreadcrumbSegment({
    super.key,
    required this.label,
    required this.onTap,
    this.isLast = false,
    this.isDragTarget = false,
  });

  @override
  State<BreadcrumbSegment> createState() => _BreadcrumbSegmentState();
}

class _BreadcrumbSegmentState extends State<BreadcrumbSegment> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FileTileColors>()!;
    final shouldHighlight = widget.isDragTarget || _isHovered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: widget.isLast ? null : widget.onTap,
              child: Container(
                decoration: shouldHighlight
                  ? BoxDecoration(
                      color: colors.overlayHover,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
                padding: shouldHighlight ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0) : EdgeInsets.zero,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.isLast ? colors.textPrimary : colors.textDim,
                    fontWeight: widget.isLast ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
          if (!widget.isLast)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: colors.textDim,
              ),
            ),
        ],
      ),
    );
  }
}
