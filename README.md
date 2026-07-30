# Stitch Desktop Grid

A Flutter widget package for creating a free-form desktop grid layout. Organize files, folders, or any items on an infinite canvas with intuitive drag-and-drop, snap-to-grid, zoom, and pan controls.

## Features

✨ **Free-form Grid Layout** - Drag items anywhere on the infinite canvas  
📌 **Snap-to-Grid** - Items automatically align to a 80px grid on drop  
🔍 **Zoom & Pan** - Scroll to zoom, drag to pan  
💾 **Persistent State** - Remembers positions, zoom levels, and colors per directory  
🎨 **Customizable Colors** - Per-item and global color settings  
📁 **File/Folder Operations** - Create, rename, delete, and navigate  
⌨️ **Script Execution** - Run bash, Python, and Node.js scripts  
🎯 **Context Menus** - Right-click for quick actions  
🔗 **Breadcrumb Navigation** - Easy path navigation with back/forward  

## Installation

1. Add to your `pubspec.yaml`:

```yaml
dependencies:
  stitch_desktop_grid:
    path: ./packages/stitch_desktop_grid
```

2. Run `flutter pub get`

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stitch_desktop_grid/stitch_desktop_grid.dart';

void main() async {
  // Initialize path service with your base directory
  await PathService.init('/home/user/my-directory');
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => DesktopViewModel(),
        child: const DesktopView(),
      ),
    );
  }
}
```

## Configuration

### PathService

Configure the base directory where the app will start:

```dart
// Must be called before using the grid
await PathService.init('/path/to/directory');

// Get the current base directory
String baseDir = PathService.baseDir;

// Get the local config file path
String configPath = PathService.localConfigPath;
```

### Customizing Colors

Set default colors for directories and files:

```dart
final viewModel = DesktopViewModel();
viewModel.directoryColor = Colors.blueAccent;
viewModel.fileColor = Colors.greenAccent;
```

## How It Works

### Data Persistence

The grid stores two types of configuration:

1. **Global Config** (`.stitch_desktop_config.json`)
   - Default folder/file colors
   - Last visited directory
   - Per-directory zoom and pan state

2. **Per-Directory Metadata** (`.stitch_desktop.json`)
   - File/folder positions
   - Custom colors per item
   - Layout version

### Grid Layout

- **Grid Size**: 80x80 pixels (default)
- **Auto-Layout**: New items automatically position in first 5 columns
- **Snap Resolution**: Items snap to 80px increments

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
│   ├── widgets/
│   │   └── breadcrumb_segment.dart # Navigation breadcrumb
│   └── services/
│       ├── path_service.dart      # Directory management
│       └── project_root_config_service.dart # Config I/O
```

### DesktopViewModel

Core state management using `ChangeNotifier`:

**Properties:**
- `currentDirectory` - Current browsing path
- `nodes` - List of visible items (files/folders)
- `scale` - Current zoom level
- `offset` - Current pan offset
- `isLoading` - Loading indicator state

**Methods:**
- `loadDirectory(path)` - Navigate to directory
- `updateNodePosition(name, delta)` - Move item
- `snapNodeToGrid(name)` - Snap item to grid
- `updateNodeColor(name, color)` - Change item color
- `createFile(name)` / `createDirectory(name)` - Create new items
- `deleteNode(name)` / `renameNode(old, new)` - Modify items
- `openWith(cmd, file)` / `openSystemDefault(file)` - Open items
- `runScript(tool, file)` / `runInTerminal(tool, file)` - Execute scripts

## Keyboard & Mouse Controls

| Action | Control |
|--------|---------|
| Zoom In | Scroll Up |
| Zoom Out | Scroll Down |
| Pan | Click + Drag |
| Context Menu | Right Click |
| Open Item | Double Click (folders) or Right Click → Open |
| Navigate Back | Back Button |
| Navigate Forward | Forward Button |

## Integration with Existing Apps

The widget is designed to be minimal and standalone. To integrate into your app:

1. **Initialize PathService** with your desired base directory
2. **Wrap DesktopView** with `ChangeNotifierProvider<DesktopViewModel>`
3. **Handle navigation** as needed in your app

Example:

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => DesktopViewModel(),
        child: Scaffold(
          appBar: AppBar(title: Text('My File Manager')),
          body: const DesktopView(),
        ),
      ),
    );
  }
}
```

## Customization

### Modify Grid Size

Edit `DesktopViewModel.gridSize`:

```dart
// In desktop_viewmodel.dart
static const double gridSize = 100.0; // Change from 80.0
```

### Modify Grid Visual

Edit `GridPainter.baseGridSize`:

```dart
// In desktop_view.dart, GridPainter class
static const double baseGridSize = 50.0; // Change from 40.0
```

### Add More Apps to "Open With"

Edit `_appRegistry` in `DesktopViewModel`:

```dart
final List<Map<String, String>> _appRegistry = [
  {'name': 'My Editor', 'cmd': 'myeditor', 'icon': 'edit'},
  // ... more apps
];
```

## Platform Support

- ✅ Linux (primary)
- ✅ macOS (with xdg-open alternatives)
- ✅ Windows (limited, no terminal integration)
- ✅ Web (file operations limited)

## Limitations

1. **Single Directory View** - Shows one directory at a time
2. **No Drag-Between-Directories** - Items can't be dragged to different folders
3. **Terminal Integration** - Limited to GNOME Terminal and x-terminal-emulator on Linux
4. **No Multi-Select** - Can't select multiple items for batch operations

## Future Enhancements

- Multi-select with Ctrl+Click
- Drag to different folders
- Custom item types/rendering
- Search/filter functionality
- Undo/redo support
- Item grouping/collections

## License

MIT

## Contributing

Contributions are welcome! Feel free to open issues or submit PRs.

---

**Made with ❤️ for the Stitch project**
