# Changelog

All notable changes to File Tile are listed here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.2] - 2026-10-20

### Fixed

- An external drag can be undone. A same-disk snapshot is kept for the drag, so the file can be restored when another app takes it and then discards it. A copy or cancelled drop puts that file back immediately.

## [0.1.1] - 2026-10-18

Feature waves scoped 2026-09-08 (Waves 1–4). Linux is the primary target; macOS and Windows support for terminal, clipboard, and drag is best-effort.

### Added

- Sticky, path-scoped layout error banner when a folder’s layout cannot be loaded (permission denied, unreadable, or corrupt JSON). Refresh retries layout IO for the current folder.
- **Open in Terminal** on folder tiles and the canvas background. Linux detects gnome-terminal, kitty, konsole, and `x-terminal-emulator`; macOS uses Terminal; Windows prefers Windows Terminal then `cmd`. Preferred emulator is saved as `preferred_terminal`. Script “Run in Terminal” uses the same launcher.
- Copy, cut, and paste for the current selection (`Ctrl/Cmd+C/X/V`, plus node and background menus). Same-folder copies auto-rename with `(copy)`; cut+paste across folders is a move; cut+paste in the same folder repositions. Recursive copy goes through `DesktopRepository.copyEntry`.
- System clipboard interchange with Files/Nautilus via `text/uri-list` and GNOME/MATE `x-special/gnome-copied-files`.
- Remappable controls in Settings (`bindings` in `file-tile-config.json`): named pointer chords for click, drag, and scroll, plus key capture for copy, cut, paste, and delete. Conflicts swap bindings instead of stacking duplicates.
- File-type Material icons, plus raster thumbnails (`jpg`, `png`, `gif`, `webp`, `bmp`) for visible cells. Bytes are read off the UI isolate; decode uses the engine codec with a target width.
- Native OS drag into and out of the window. Drop on empty canvas, a folder tile, or a breadcrumb. Default drop is a **move**; hold Ctrl to copy. Incoming GNOME `copy`/`cut` verbs still win. Hover shows a dotted destination overlay.
- Optional sqlite layout storage (`metadata_backend: json | sqlite`, default JSON). Positions and new-element placement can live in `file-tile-layout.sqlite` next to config, so unwritable folders can still keep a layout. Switching backends copy-then-wipes known directories only (never walks `$HOME`). If the preferred store fails, a leftover store is used and a fallback banner is shown.
- Undo and redo (`Ctrl/Cmd+Z`, `Ctrl/Cmd+Shift+Z`) for creates, moves, and deletes. Delete sends the item to the trash, and undo puts it back.
- New symlink from the canvas menu, using the system file picker to choose the target.
- AppImage self-update from GitHub Releases. On startup a packaged build asks before installing a delta update, then offers to restart.
- Canvas edge auto-scroll while dragging, and multi-file drops that keep each file on the cell relative to the pointer.

### Changed

- Default scroll mappings: scroll zooms; Ctrl+scroll pans horizontally; Shift+scroll pans vertically (previously Ctrl+scroll zoomed).
- Dragging a tile starts a native file drag instead of panning that tile on the canvas. Empty-canvas pan and the selection box are unchanged. Dropping a tile back on File Tile uses the same import path as an external drop.
- Layout IO failures no longer persist a wiped default layout for a blocked path. Polling no longer snackbar-spams on those errors; other errors still toast (existing snackbars are cleared first). View-state save failures latch once.
- Canvas pointer math uses the canvas `RenderBox`, so the layout banner does not offset clicks.

### Fixed

- Breadcrumb flicker: stable keys reused by path, hover padding always reserved, and the loading spinner only when the listing is empty.

### Notes

- Directory search (app-bar filter, including nested walk) is implemented enough to exist in the tree but is commented out and not shipping in this batch.
- Video/PDF thumbnails, URL drops, and creating symlinks on drop are out of scope.
- Theme, zoom/pan view states, last directory, preferred terminal, bindings, and the backend flag stay in `file-tile-config.json`. Per-directory tile positions remain JSON (`file-tile.json`) unless sqlite mode is on.
