import 'trash_token.dart';

/// Session undo/redo stack. Not written to disk.
class EditHistory {
  static const limit = 50;

  final List<EditEntry> _undo = [];
  final List<EditEntry> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(EditEntry entry) {
    _undo.add(entry);
    while (_undo.length > limit) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  EditEntry? takeUndo() => _undo.isEmpty ? null : _undo.removeLast();

  EditEntry? takeRedo() => _redo.isEmpty ? null : _redo.removeLast();

  /// Put an entry back after a failed undo. Does not clear redo.
  void noteUndo(EditEntry entry) => _undo.add(entry);

  /// Remember an entry that was just undone.
  void noteRedo(EditEntry entry) => _redo.add(entry);
}

sealed class EditEntry {}

class MoveEditItem {
  final String sourceDir;
  final String name;
  final Map<String, dynamic>? sourceLayout;
  final Map<String, dynamic>? destLayout;

  const MoveEditItem({
    required this.sourceDir,
    required this.name,
    required this.sourceLayout,
    required this.destLayout,
  });
}

class MoveEdit extends EditEntry {
  final String destDir;
  final List<MoveEditItem> items;

  MoveEdit({required this.destDir, required this.items});
}

class CreatedEditItem {
  final String name;
  final Map<String, dynamic>? layout;

  const CreatedEditItem({required this.name, required this.layout});
}

/// A file, folder, symlink, or copy that did not exist before the edit.
/// [tokens] is filled in when the create is undone and the paths are trashed.
class CreatedEdit extends EditEntry {
  final String directory;
  final List<CreatedEditItem> items;
  final List<TrashToken?> tokens;

  CreatedEdit({
    required this.directory,
    required this.items,
    required this.tokens,
  });
}

class DeletedEditItem {
  final String directory;
  final String name;
  final Map<String, dynamic>? layout;
  TrashToken token;

  DeletedEditItem({
    required this.directory,
    required this.name,
    required this.layout,
    required this.token,
  });
}

class DeletedEdit extends EditEntry {
  final List<DeletedEditItem> items;

  DeletedEdit(this.items);
}

class RenameEdit extends EditEntry {
  final String directory;
  final String oldName;
  final String newName;

  RenameEdit({
    required this.directory,
    required this.oldName,
    required this.newName,
  });
}

/// Position or color change in one directory.
class LayoutEdit extends EditEntry {
  final String directory;
  final Map<String, Map<String, dynamic>> before;
  final Map<String, Map<String, dynamic>> after;

  LayoutEdit({
    required this.directory,
    required this.before,
    required this.after,
  });
}
