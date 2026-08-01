# Architecture alignment plan

Follow-up to the alignment review against [flutter-best-practices.md](flutter/flutter-best-practices.md). Covers the four highest-leverage gaps, in priority order. Each unlocks the next: repository extraction unlocks testing; immutable models make the repository's output easy to reason about; error surfacing depends on having a real place (the repository) to catch and report failures.

---

## 1. Repository abstraction for filesystem access

**Problem:** `PathService`, `ProjectRootConfigService`, `ConfigManager`, and `MetadataManager` are static classes/singletons that call `dart:io` directly. `DesktopViewModel` talks to them by static reference, so there's no seam to fake the filesystem in a test and no way to swap implementations.

**Plan:**
- Define an abstract `DesktopRepository` with the operations `DesktopViewModel` currently performs against the filesystem: `listEntities(path)`, `createFile`, `createDirectory`, `delete`, `rename`, `readConfig`, `updateConfig`, `readLayout(path)`, `updateLayout(path, layout)`.
- Implement `FileSystemDesktopRepository` that wraps the existing `dart:io`, `ConfigManager`, and `MetadataManager` logic — mostly moving existing code, not rewriting it.
- Give `DesktopViewModel` a constructor parameter `DesktopRepository repository`, defaulting to `FileSystemDesktopRepository()` in `main.dart`'s `ChangeNotifierProvider(create: ...)` so no other call site needs to change.
- Delete the static-singleton entry points on `ProjectRootConfigService`/`PathService` once nothing else calls them directly (`MetadataManager` can stay as an internal implementation detail of the repository).

---

## 2. Immutable `DesktopNode`

**Problem:** `DesktopNode.position` and `.color` are mutable fields, and the ViewModel mutates list entries in place (`_nodes[index].position += delta`). This bypasses unidirectional data flow — nothing forces state changes to go through a single, observable point.

**Plan:**
- Make `DesktopNode` immutable: `final Offset position`, `final Color? color`, plus a `copyWith({position, color})` method.
- Replace every in-place mutation site (`updateNodePosition`, `snapNodeToGrid`, `updateNodeColor`, the load/create paths) with `_nodes[index] = _nodes[index].copyWith(...)` followed by reassigning `_nodes = List.unmodifiable([...])` or a new list.
- No consumer-facing API changes — `DesktopNode.toJson()` and the `nodes` getter keep their current shape, so `desktop_view.dart` needs no changes.

---

## 3. Centralized, visible error handling

**Problem:** Nearly every catch block (`openWith`, `openSystemDefault`, `_init`, `loadDirectory`, `deleteNode`, `renameNode`, config read/write) does `debugPrint` and swallows the error. Failures are invisible to the user.

**Plan:**
- Add a single `String? lastError` field (+ getter) to `DesktopViewModel`, set via a private `_setError(String message)` that also calls `notifyListeners()`.
- Route every existing catch block through `_setError` instead of (or in addition to) `debugPrint`, using short user-facing messages ("Couldn't delete stitch-grid.json", "Couldn't open with VS Code").
- In `desktop_view.dart`, wrap the `Scaffold` body in a listener (e.g. compare `lastError` in `didUpdateWidget`/a `ProxyProvider` listener, or simplest: check it at the top of `build` and fire `ScaffoldMessenger.of(context).showSnackBar` once, then have the ViewModel clear `lastError` after reading) — this becomes the app's one error-handling surface, matching the "surface errors clearly" recommendation without introducing a new package.
- This step depends on (1): once filesystem calls go through `DesktopRepository`, the repository methods can return a `Result`-like type (or throw a typed exception) that the ViewModel translates into a message, rather than parsing raw `dart:io` exceptions.

---

## 4. Unit tests for `DesktopViewModel` and services

**Problem:** Only `test/coordinate_space_test.dart` exists. The ViewModel (~570 lines, the most stateful class in the app) and all services are untested, and were previously untestable because they hit the real filesystem via static singletons.

**Plan:** (depends on step 1)
- Add `FakeDesktopRepository implements DesktopRepository` backed by in-memory maps (path → entities, path → layout, config map) — no real file I/O.
- Write `test/desktop_viewmodel_test.dart` covering: `loadDirectory` (positions restored from layout, unpositioned files get grid-packed), `createFile`/`createDirectory`, `deleteNode` + `performSelectAction(delete)` for multi-select, `renameNode`, `back`/`forward` history, and color/scroll setting persistence calls.
- Write a small test for `_setError` surfacing once step 3 lands (repository throws → `lastError` is set).
- Leave `desktop_view.dart` widget tests out of this first pass — the ViewModel test suite is the higher-value gap; a light `pumpWidget` smoke test can follow once the ViewModel is stable.
