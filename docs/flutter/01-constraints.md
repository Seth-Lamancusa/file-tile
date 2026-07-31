# Flutter Layout Constraints Documentation

Source: https://docs.flutter.dev/ui/layout/constraints

## Core Principle

**Constraints go down. Sizes go up. Parent sets position.**

This three-part rule governs all Flutter layout:

1. **Constraints down**: Parents pass constraints (min/max width/height) to children
2. **Sizes up**: Children report their desired sizes back to parents
3. **Position set**: Parents position children based on available space

## The Layout Negotiation Process

When laying out widgets, the negotiation flows like this:

- Parent tells child: "You must be between X and Y pixels wide/tall"
- Child considers constraints and reports: "I want to be Z pixels"
- Parent positions the child and reports its own size to its parent

## Key Limitations

Flutter's one-pass layout system has built-in constraints:

- **Widgets can't choose their own size** outside parent constraints
- **Widgets can't know their position** on screen (parent decides)
- **Child size can be ignored** if parent lacks alignment information
- **Tree-wide consideration required** to determine final sizes/positions

## Types of Constraint-Handling Boxes

1. **Try to be as big as possible**: `Center`, `ListView`
2. **Match child size**: `Transform`, `Opacity`
3. **Be a particular size**: `Image`, `Text`
4. **Variable behavior**: `Container`, `Row`, `Column` (depends on parameters)

## Common Widgets Explained

- **`Center`**: Allows child any size (up to screen), centers it
- **`Align`**: Like Center but aligns to specified position instead
- **`ConstrainedBox`**: Adds additional constraints on top of parent's
- **`UnconstrainedBox`**: Removes parent constraints (may cause overflow)
- **`FittedBox`**: Scales child to fit available space
- **`Expanded`/`Flexible`**: In Row/Column, distributes space among children

The documentation includes 29 interactive examples demonstrating these concepts in practice.
