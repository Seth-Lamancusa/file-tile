# Select Actions Pattern

Select actions are operations that act on one or more selected items. They serve as the interface between the selection system and node operations.

## DesktopSelectAction Enum

All available select actions are defined in `DesktopSelectAction` enum in `desktop_viewmodel.dart`. This is the single source of truth for what actions can operate on selections.

Currently defined:
- `delete` — remove one or more selected nodes

## Selection Model

The viewmodel maintains a `Set<String>` of selected node names. Multiple items can be selected simultaneously using Ctrl+click. Selection state is not persisted across directory navigations.

## Implementing a New Select Action

1. Add the action to the `SelectAction` enum
2. Add a handler method to `DesktopViewModel` (e.g., `_performDelete`)
3. Add a menu item or keyboard binding that calls `performSelectAction`
4. Update the confirmation dialog if needed to handle multiple items

## Delete Action Implementation

The delete action is the pattern to follow. It:
1. Collects all selected node names from the viewmodel
2. Shows a confirmation dialog listing items to be deleted
3. Performs deletion on each item
4. Reloads the directory when complete
