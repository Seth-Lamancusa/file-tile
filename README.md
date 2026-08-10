# Stitch Desktop Grid

⊞

A free-form desktop grid. Organize files, folders, or other items on an infinite canvas with drag-and-drop, zoom, and pan controls.

## Features

✨ **Free-form Grid Layout** - Drag items anywhere on the infinite canvas with zoom and pan
🎨 **Customizable Colors** - Color your folders for easy recognition  
📁 **File/Folder Operations** - Create files and folders and run scripts

## How It Works

### Data Persistence

The grid stores two types of configuration:

1. **Global Config** (`stitch-grid-config.json`)
   - Default folder/file colors
   - Last visited directory
   - Per-directory zoom and pan state

2. **Per-Directory Metadata** (`stitch-grid.json`)
   - File/folder positions
   - Custom colors per item
   - Layout version

### Grid Layout

- **Grid Size**: 80x80 pixels (default)
- **Auto-Layout**: New items automatically position in first 5 columns
- **Snap Resolution**: Items snap to 80px increments

### Coordinate System

The grid uses **1-based indexing with no zero**:
- Grid cells are indexed: `..., -2, -1, 1, 2, 3, ...` (0 is skipped)
- Grid cell 1 occupies logical pixels 0–80
- Grid cell -1 occupies logical pixels -80 to 0
- When calculating positions or placement regions, any result of 0 must be adjusted to 1 (moving positive) or -1 (moving negative)

### Available Apps

The "Open With" menu supports:
- VS Code (`code`)
- Cursor (`cursor`)
- Sublime Text (`subl`)
- Nautilus (`nautilus`)

Availability is automatically detected via the `which` command.

## Architecture

```
lib/
├── stitch_desktop_grid.dart       # Main export
├── src/
│   ├── views/
│   │   └── desktop_view.dart      # Main UI widget
│   ├── viewmodels/
│   │   └── desktop_viewmodel.dart # State management
│   ├── repositories/
│   │   ├── desktop_repository.dart            # Abstract repository interface
│   │   └── file_system_desktop_repository.dart # File system implementation
│   ├── widgets/
│   │   ├── breadcrumb_segment.dart # Navigation breadcrumb
│   │   └── cascading_menu.dart     # Context menu widget
│   ├── services/
│   │   └── path_service.dart      # Directory management
│   └── utils/
│       ├── config_manager.dart     # Config I/O and persistence
│       ├── json_file_manager.dart  # JSON file handling
│       ├── metadata_helper.dart    # Metadata utilities
│       └── coordinate_space.dart   # Coordinate transformations
```

### Notes

**Operation Serialization**
All disk-touching operations (load, create, delete, rename, move, and polling) are serialized via a single operation queue (`_operationChain` in `DesktopViewModel`). This prevents races where a stale operation could finish late and clobber a newer one. Avoid wrapping operations in nested `_runExclusive` calls — if you're already inside one, call the `_impl` variant directly instead.

**Polling Suspension During Interaction**
Polling is suspended during drags, pans, and selection-box gestures via `beginInteraction()`/`endInteraction()`. This prevents a background reload from clobbering unsaved, in-memory UI state like a node position mid-drag. If you add a new user gesture, wrap it with these calls in the view's event handler.

**Dialog & Menu Sizing**
To properly control width on an `AlertDialog`:
- **Set `insetPadding`** on the `AlertDialog` (e.g., `EdgeInsets.symmetric(horizontal: 20.0)`)
- **Wrap content in `SizedBox`** with the desired width, using `MediaQuery.of(context).size.width * 0.33` for responsive sizing

**Best Practices**
When implementing new features,
- Refer to `/docs/flutter/flutter-best-practices.md` for guidance

## Keyboard & Mouse Controls

| Action | Control |
|--------|---------|
| Zoom In | Ctrl + Scroll Up |
| Zoom Out | Ctrl + Scroll Down |
| Pan | Click + Drag |
| Pan (Horizontal) | Shift + Scroll |
| Selection Box | Shift + Drag |
| Select Single | Left Click |
| Toggle Select | Ctrl + Click |
| Range Select | Shift + Click |
| Context Menu | Right Click |
| Open Item | Double Click (folders) or Right Click → Open |
| Delete Selected | Delete Key |
| Navigate Back | Back Button |
| Navigate Forward | Forward Button |

### Add More Apps to "Open With"

Edit `_appRegistry` in `DesktopViewModel`:

```dart
final List<Map<String, String>> _appRegistry = [
  {'name': 'My Editor', 'cmd': 'myeditor', 'icon': 'edit'},
  // ... more apps
];
```

## Build Instructions

`dart pub global activate flutter_distributor` if not yet run.
`flutter_distributor release --name production`

## Future Enhancements

- Search/filter functionality
- Undo/redo support

## License

MIT

## Contributing

Contributions are welcome! Feel free to open issues or submit PRs.

## Notes

When in doubt, see /docs. There are plans for ongoing work, as well as internal and external documentation files addressing existing implementations and common patterns or pain points.

---

**Made with ❤️ for the Stitch project**
