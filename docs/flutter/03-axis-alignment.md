# Axis Alignment of Columns and Rows in Flutter

Source: https://medium.com/@themobilecoder/axis-alignment-of-columns-and-rows-in-flutter-e7da890e556b

## Overview

This guide explains how to position child widgets within Flutter's `Column` and `Row` layout widgets using alignment properties.

## Key Concepts

**Main Axis Orientation:**
- `Column` widgets arrange children vertically (Y-Axis as main axis)
- `Row` widgets arrange children horizontally (X-Axis as main axis)

**mainAxisAlignment Property:**

This controls widget positioning along the primary axis:
- **start**: Widgets move to top (Column) or left (Row)
- **end**: Widgets move to bottom (Column) or right (Row)
- **center**: Widgets center along the axis
- **spaceBetween**: Equal spacing between widgets
- **spaceAround**: Even spacing with half-space at edges
- **spaceEvenly**: Equal spacing including edges

**crossAxisAlignment Property:**

This controls positioning perpendicular to the main axis:
- **start/end**: Align to edges
- **center**: Center on cross-axis
- **stretch**: Fills available space
- **baseline**: Aligns text baselines (text widgets only)

## Important Note

"Using CrossAxisAlignment.stretch would throw a BoxConstraints error if the parent widget lacks constrained width," such as when nested in another Row or Column.

**Solution**: Wrap the parent with `IntrinsicWidth` to provide bounded constraints before using `crossAxisAlignment: CrossAxisAlignment.stretch`.

## Takeaway

Master these two properties to effectively control widget positioning in Flutter layouts.
