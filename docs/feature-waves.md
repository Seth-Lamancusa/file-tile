# Feature waves

Roadmap for the File Tile batch scoped 2026-09-08. **Waves 1–3 and Wave 4a are done.** Wave 4b is sqlite layout storage.

Suggested order: Wave 1 (stabilize) → Wave 2 (file ops) → Wave 3 (input + visuals) → Wave 4 (platform + storage). Do not combine Drift, OS drag-and-drop, and thumbnails in one PR.

Linux is the primary target. macOS/Windows for terminal, clipboard, and drag are extra time inside the L items.

---

## Wave 1 — stabilize (done)

### Permission error surfacing

Path-scoped `DirectoryLayoutIssue` (`lib/src/models/directory_layout_issue.dart`) with a sticky banner while that directory is open. Layout IO failures are classified in `lib/src/utils/io_errors.dart` (EACCES vs corrupt JSON vs other). Blocked paths skip `ensure`/`updateLayout` so a failed read cannot persist a wiped default layout. Polling no longer snackbar-spams. Other errors still use snackbars (`clearSnackBars` first); view-state save failures latch once. Refresh retries layout IO for the current folder.

### Breadcrumb flicker

Stable `GlobalKey`s reused by path in `_buildBreadcrumbs`. Hover padding always reserved. Loading spinner only when `nodes.isEmpty`. Canvas pointer math uses the canvas `RenderBox` (`_globalToCanvas`) so the banner does not throw off clicks.

### Also in this wave

- Restored `DesktopViewModel` export from `lib/file_tile.dart` (needed by `main.dart`).
- Tests: `test/io_errors_test.dart`, layout-issue cases in `test/desktop_viewmodel_test.dart`.

---

## Wave 2 — file ops (done)

Copy/paste is the hinge for Wave 4 drag.

### Open in Terminal (done)

Node menu (folders only) and background menu open a detected emulator. Linux: gnome-terminal, kitty, konsole, x-terminal-emulator (PATH plus common extra bins). macOS Terminal; Windows `wt` then `cmd`. Preferred emulator in `preferred_terminal`. Script “Run in Terminal” uses the same launcher.

### Copy / paste (done, v1)

In-app clipboard (paths + cut vs copy). Ctrl/Cmd+C/X/V. Copy/Cut on the node menu (whole selection). Paste on the background menu at the click cell. Same-folder copy auto-renames (`(copy)`). Cross-folder name clashes use the existing conflict dialog. Cut+paste across folders is a move; cut+paste in the same folder repositions. Recursive copy via `DesktopRepository.copyEntry`. System clipboard via `super_clipboard`: `text/uri-list` plus GNOME/MATE `x-special/gnome-copied-files` so Files/Nautilus can paste in and out.

### Search directory (deferred)

Commented out for now. App-bar search (also Ctrl/Cmd+F). Instant filter of the current listing with highlight + pan-to. **Include nested**: streamed walk, cancelled on nav/new query, paused during interaction, unlistable subdirs skipped with no snackbar flood. Nested hits are path rows (not tiles); tap opens the parent and selects.

---

## Wave 3 — input + visuals (done)

### Custom controls (done)

`ControlAction` + `BindingMap` in `file-tile-config.json` (`bindings`). Settings remap UI with conflict swap for pointer chords and key capture for copy/cut/paste/delete. Mouse input is a closed set of named chords (click / drag / scroll + modifiers), not free-form mouse programming. Defaults match the previous hardcoded behavior: scroll = zoom, Ctrl+scroll = horizontal pan, Shift+scroll = vertical pan.

### Thumbnails and icons (done)

Extension → Material icon map (`lib/src/utils/file_icons.dart`). Raster image thumbs (`jpg/png/gif/webp/bmp`) cached by path, loaded only for visible cells. File bytes read in `Isolate.run`; decode uses the engine codec with `targetWidth`. No video/PDF thumbs in v1.

---

## Wave 4 — platform + storage

Two PRs. Do not land OS drop and Drift together.

Linux is the acceptance OS. macOS/Windows drag and extra sqlite packaging are extra time, not blockers.

---

### 4a — OS drag into / out of window (done)

**Depends on:** Wave 2 copy/paste. Shared formats live in `lib/src/utils/os_file_clipboard.dart` (`text/uri-list`, `x-special/gnome-copied-files`). Shared IO is `DesktopRepository.copyEntry` / `rename` plus `MoveConflictException` and `_placePastedNodes`.

In-app tile pan is gone. Dragging a tile starts a native file drag. Dropping back on the canvas uses the same overlay + `importPaths` as drag-in (reposition or drop into a folder). Dropping in another app is a file move unless Ctrl is held (copy). Empty-canvas pan and the selection box are unchanged.

#### Extract one import path (do this first, small)

Pull `_pasteImpl`’s “here are source paths + cut vs copy + drop cell” work into something like `importPaths(paths, {required bool isCut, Offset? at, bool skipConflicts})`. `paste()` becomes: resolve clipboard → `importPaths`. Drop uses the same method. Same-folder copy still auto-renames; cross-folder clashes still throw `MoveConflictException`; cut across folders is a move; invalid “into itself” still snackbars.

#### 4a.1 Drag-in (must ship)

Wrap the canvas (not the whole scaffold) in a `super_drag_and_drop` `DropRegion` (or equivalent). Incoming payloads:

1. GNOME/MATE `x-special/gnome-copied-files` (verb + `file://` URIs) — honor `copy` vs `cut`
2. `text/uri-list`
3. `Formats.fileUri` / file items

Ignore non-`file://` URIs. Empty drop is a no-op.

Drop targets:

| Hit | Behavior |
|-----|----------|
| Empty canvas | import into the current directory; place at the snapped click cell (same as background Paste) |
| Folder tile | import into that folder (same conflict rules as `moveNodesToDirectory`); do not leave tiles in the current listing unless it was a same-folder drop |
| Breadcrumb | import into that path |
| Window chrome / menus | not a drop target |

Default operation when the payload has no verb: **move**. Ctrl held → copy. Incoming GNOME `copy` / `cut` verbs still win over the default.

Visual: while a valid file drop is hovering, overlay the **destination cell** (snapped grid cell on empty canvas, or the folder tile if hovering a folder) with a dotted box and a drop/add-file glyph. Hovering a breadcrumb uses the same dotted treatment on that segment. Reject (no overlay, no import) if every URI is non-file.

Polling: treat the drop like any other disk-touching op (`_runExclusive`). `beginInteraction`/`endInteraction` around the pointer hover/drop so a poll cannot clobber placement.

Tests: parse helpers already exist — add drop-session tests that feed `OsFileClipboardSnapshot` into `importPaths` (fake repo). Widget-level DropRegion can stay light.

#### 4a.2 Drag-out (done)

Dragging a tile starts a native session (`super_drag_and_drop`). Tap / double-click still use the tile `GestureDetector`. Empty canvas pan is unchanged.

Payload: same encodings as clipboard write. **Only `DropOperation.move` is offered** unless Ctrl is held at drag-start (`copy`). Offering both is why Files was copying. GNOME payload verb matches (`cut` vs `copy`). After a successful external move, `finalizeExternalMove` removes leftovers and reloads. Cancel or copy → source tiles stay. Dropping back on File Tile is a local import (not a second delete).

macOS/Windows: drag-in via `file://` is best-effort; gnome format is Linux-only.

**Out of scope:** dragging URLs, `.desktop` launchers as text, linking (`ln -s`) as a drop operation.

---

### 4b — DB mode, Drift (L, ~4–6 days)

**Depends on:** Wave 1 layout-issue banner and `DesktopRepository` layout methods. Does **not** depend on 4a.

JSON `file-tile.json` in the visited folder is the default. Sqlite is opt-in so unwritable directories can still store positions (Wave 1 banner is the JSON-mode UX; sqlite is the structural fix).

On switch, copy then wipe the inactive store for **known** directories only (never walk `$HOME`). JSON → sqlite: import `desktop_view_states` keys, last visited directory, and existing DB paths, then best-effort delete those `file-tile.json` / `stitch-grid.json` files. sqlite → JSON: export each DB path to JSON, then delete those DB rows. Never delete the only successful copy: failed delete leaves JSON while sqlite is source of truth; failed export keeps the DB row.

Runtime fallback is dynamic on layout IO: prefer the configured backend when it has a usable copy; if it doesn't and the leftover store still does, use the leftover and show `storageFallback`. Do not merge stores. Writes stay on the live home. `ensureLayoutFileExists` must not create an empty JSON file that would hide a sqlite leftover.

#### What moves into sqlite

Only per-directory **layout** and **new-element placement**. Keep in JSON `file-tile-config.json`: theme, scroll invert, `desktop_view_states`, last directory, `preferred_terminal`, `bindings`, and the new `metadata_backend` flag.

File create/delete/rename/copy stay on the real filesystem. `listEntities` does not change.

#### Seam

Do not fork `DesktopViewModel`. Keep `DesktopRepository` as the ViewModel’s only storage API.

Add an internal layout store used by `FileSystemDesktopRepository` (or a thin wrapper that picks json vs sqlite at construction):

- `ensureLayoutFileExists` — json: create `file-tile.json` in the folder; sqlite: no-op (row created on first write)
- `readLayout` / `updateLayout` / `removeFromLayout` / `renameInLayout`
- `readNewElementPlacementConfig` / `updateNewElementPlacementConfig`

Json implementation stays `MetadataManager`. Sqlite implementation is Drift, database file in the user config dir (next to `file-tile-config.json`), keyed by **absolute directory path**.

Suggested tables (keep the on-disk JSON shape, don’t invent a new layout dialect):

- `layout_node(path TEXT, name TEXT, payload TEXT, PRIMARY KEY (path, name))` — value is the existing per-name layout object
- `directory_meta(path TEXT PRIMARY KEY, placement_json TEXT, version TEXT)` — import sentinel

Atomicity: one transaction per `updateLayout` / `removeFromLayout` / `renameInLayout`. Still go through `_operationChain` in the ViewModel.

#### Toggle and migrate

`metadata_backend: json | sqlite` in config (default `json`). Settings row to switch. Switching runs copy-then-wipe immediately inside `_runExclusive`, then reloads the current directory. Don’t hot-swap mid-gesture.

Migrate **known** directories only — never walk `$HOME`:

1. Keys of `desktop_view_states`
2. Last visited directory
3. Paths already in the DB (leftovers)
4. On each later `loadDirectory`, if sqlite is on and JSON exists for that path and the DB has no row yet, import then best-effort wipe JSON

Import is read JSON → write DB inside `_runExclusive`. Failures: path-scoped `layoutIssue` (permission / corrupt / unreadable), same as Wave 1. Do not snackbar-spam. Do not wipe the JSON on failed import.

**After a successful import: wipe JSON when that delete succeeds.** Leftover JSON is only for failed deletes. Switching back to json writes `file-tile.json` where the folder is writable, then drops those DB rows. If unwritable, keep the DB row, stay on leftover sqlite, and show the fallback banner.

`ensure`/`updateLayout` skip rules from Wave 1 apply when layout IO is blocked (permission / corrupt / unreadable with no leftover). `storageFallback` does not skip writes. Sqlite writes to the config dir, so a permission-denied **folder** must not block layout save in sqlite mode. Listing that folder can still fail; that’s a snackbar, not `layoutIssue`.

#### Tests

- Fake store already covers ViewModel. Add a Drift (or in-memory sqlite) store test: round-trip layout, rename node, skip migrate when DB already has the path, import from a temp `file-tile.json`, failed import sets issue and does not insert a wiped default.
- Existing `test/verify_real_fs_test.dart` remains the json-backend contract.

**Out of scope:** storing file bytes, search index, undo history, crawling the home directory, per-directory backend mix (one global flag).

---

## Shared seams (do not reinvent)

| Seam | Today | Reuse for |
|------|--------|-----------|
| `DesktopRepository` | list/create/delete/rename/copy + layout/config | Drift |
| `_operationChain` | serializes disk-touching work | migrate |
| `layoutIssue` + snackbars | path-scoped banner; one-shot toasts | migrate failures |
| `DesktopSelectAction` | delete, openInTerminal, copy, cut | menus |
| `BindingMap` | remappable keys + named pointer chords | search, when re-enabled |
| `file-tile-config.json` | theme, scroll invert, view states, last dir, preferred terminal, bindings | `metadata_backend` |
| `os_file_clipboard.dart` | gnome + uri-list parse/encode | OS drop payloads |
| `_pasteImpl` / `MoveConflictException` | copy vs move, conflicts, placement | `importPaths` for drop |

---

## Open decisions

1. After sqlite import: wipe JSON (best-effort) vs leave in place. **Resolved: copy then wipe the inactive store; leftovers only on permission failures.**
2. Copy/paste and OS-drop default: copy vs move. **Resolved for OS drag: move unless Ctrl (copy).** Incoming GNOME `copy`/`cut` still win. In-app Ctrl+C/V stays copy. Do not infer same-volume vs other-volume.
3. Binding registry in Wave 2 plumbing vs wait for Wave 3. Waiting avoids a settings UI with three actions. **Resolved: Wave 3 `BindingMap`.**
4. Thumbnail decode in-process vs isolate pool. **Resolved: isolate for file IO; engine codec for pixels.**
5. OS drag-out vs in-app pan. **Resolved: tile drag is always native.** Local drop uses the drag-in overlay; empty-canvas pan is unchanged. Ctrl copies.
