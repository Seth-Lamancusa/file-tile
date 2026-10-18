# File Tile

⊞

A free-form desktop grid. Organize files, folders, or other items on an infinite canvas with drag-and-drop, zoom, and pan controls.

## Features

✨ **Free-form Grid Layout** - Drag items anywhere on the infinite canvas with zoom and pan
🎨 **Customizable Colors** - Color your folders for easy recognition  
📁 **File/Folder Operations** - Create files and folders and run scripts

## How It Works

### Data Persistence

The grid stores two types of configuration:

1. **Global Config** (`file-tile-config.json`)
  - Default folder/file colors
  - Last visited directory
  - Per-directory zoom and pan state
2. **Per-Directory Metadata** (`file-tile.json`)
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
├── file_tile.dart                 # Main export
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

- **Set** `insetPadding` on the `AlertDialog` (e.g., `EdgeInsets.symmetric(horizontal: 20.0)`)
- **Wrap content in** `SizedBox` with the desired width, using `MediaQuery.of(context).size.width * 0.33` for responsive sizing

**Best Practices**
When implementing new features,

- Refer to `/docs/flutter/flutter-best-practices.md` for guidance



## Keyboard & Mouse Controls

Defaults (remappable in Settings except pan, right-click, and double-click):

| Action           | Control                                      |
| ---------------- | -------------------------------------------- |
| Zoom             | Scroll                                       |
| Pan              | Click + Drag                                 |
| Pan (Vertical)   | Shift + Scroll                               |
| Pan (Horizontal) | Ctrl + Scroll                                |
| Selection Box    | Shift + Drag                                 |
| Select Single    | Left Click                                   |
| Toggle Select    | Ctrl + Click                                 |
| Range Select     | Shift + Click                                |
| Context Menu     | Right Click                                  |
| Open Item        | Double Click (folders) or Right Click → Open |
| Copy / Cut / Paste | Ctrl/Cmd + C / X / V                       |
| Delete Selected  | Delete Key                                   |
| Navigate Back    | Back Button                                  |
| Navigate Forward | Forward Button                               |




### Add More Apps to "Open With"

Edit `_appRegistry` in `DesktopViewModel`:

```dart
final List<Map<String, String>> _appRegistry = [
  {'name': 'My Editor', 'cmd': 'myeditor', 'icon': 'edit'},
  // ... more apps
];
```



## Build Instructions

Install the packager once:

`dart pub global activate flutter_distributor`

Build the AppImage:

`linux/packaging/appimage/release.sh`

Use that script instead of calling `flutter_distributor` directly. It puts a small `appimagetool` wrapper first on `PATH`, and `flutter_distributor` does not pass update information on its own. The wrapper reads `linux/packaging/appimage/update_information` and forwards it as `appimagetool --updateinformation`.

The build machine also needs the real `appimagetool` on `PATH`, and `zsync` (`sudo apt install zsync`) so `zsyncmake` can write a `.zsync` file next to the AppImage. Without `zsync`, the AppImage still builds, but clients cannot delta-update to it.

Output lands in `dist/<version>/`, for example `dist/0.1.1/file_tile-0.1.1-linux.AppImage` and `file_tile-0.1.1-linux.AppImage.zsync`.

### Self-update

People who download the AppImage do not install `zsync`, `appimagetool`, or `appimageupdatetool`. Those first two are build tools. The updater is copied into the AppImage automatically when it is packaged, and the running app calls that bundled copy.

Release AppImages update themselves from GitHub Releases on [Seth-Lamancusa/file-tile](https://github.com/Seth-Lamancusa/file-tile). The embedded update string is:

```
gh-releases-zsync|Seth-Lamancusa|file-tile|latest|file_tile-*linux.AppImage.zsync
```

`latest` means the newest GitHub Release. The last field is a filename glob for the `.zsync` asset. `appimageupdatetool` uses that file to download only the changed bytes.

At package time, `linux/packaging/appimage/bundle_updater.sh` (a `flutter_distributor` pre-hook) downloads `appimageupdatetool` into `linux/packaging/appimage/.cache/` and copies it to `usr/bin/appimageupdatetool` inside the AppImage. The cache directory is gitignored.

On startup, when `$APPIMAGE` is set, the app runs:

```bash
appimageupdatetool --check-for-update "$APPIMAGE"
```

Exit code 1 means an update is available. The app then shows **New update available. Install now?** Choosing Install now runs `appimageupdatetool --overwrite "$APPIMAGE"`, which replaces the file on disk while this process keeps running, then offers a restart. **Not now** leaves the session as it is. A `flutter run` build has no `$APPIMAGE`, so it never asks.

To publish a build that installed copies can update to:

```bash
sudo apt install zsync gh
gh auth login
linux/packaging/appimage/publish_github.sh
```

`publish_github.sh` packages, then uploads both the `.AppImage` and the `.AppImage.zsync` to the release tagged `v<version>` from `pubspec.yaml` (currently `v0.1.1`). If that release already exists, the two assets are replaced. Pass `--skip-build` to upload files already in `dist/<version>/`.

The first published AppImage is the baseline. The update dialog appears after a newer release is published with both assets. An AppImage built before the update string was embedded cannot update itself.

## Future Enhancements

- Search/filter functionality
- Undo/redo support



## License

MIT

## Contributing

Contributions are welcome! Feel free to open issues or submit PRs.

## Notes

When in doubt, see `/docs`. There are also plans for ongoing work, plus internal and external documentation addressing existing implementations and common patterns or pain points.

---

**Made with ❤️**