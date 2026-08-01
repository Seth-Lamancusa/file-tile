import 'package:flutter/material.dart';

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
    final shouldHighlight = widget.isDragTarget || _isHovered;

    return InkWell(
      onTap: widget.isLast ? null : widget.onTap,
      borderRadius: BorderRadius.circular(4),
      onHover: (isHovering) {
        setState(() => _isHovered = isHovering);
      },
      splashColor: shouldHighlight ? Colors.transparent : null,
      highlightColor: shouldHighlight ? Colors.transparent : null,
      hoverColor: shouldHighlight ? Colors.transparent : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: shouldHighlight
                ? BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
              padding: shouldHighlight ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0) : EdgeInsets.zero,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.isLast ? Colors.white : Colors.grey,
                  fontWeight: widget.isLast ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (!widget.isLast)
              const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
