import 'package:flutter/material.dart';

class BreadcrumbSegment extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLast ? null : onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: isDragTarget
          ? BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isLast ? Colors.white : Colors.grey,
                  fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (!isLast)
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
      ),
    );
  }
}
