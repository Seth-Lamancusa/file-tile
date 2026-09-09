/// Why per-directory layout metadata could not be loaded or saved.
enum DirectoryLayoutIssueKind {
  permissionDenied,
  unreadable,
  corrupt,
  storageFallback,
}

/// Sticky, path-scoped layout problem shown while that directory is open.
class DirectoryLayoutIssue {
  final String path;
  final DirectoryLayoutIssueKind kind;

  const DirectoryLayoutIssue({required this.path, required this.kind});

  String get message {
    switch (kind) {
      case DirectoryLayoutIssueKind.permissionDenied:
        return "Couldn't load saved layout for this folder (permission denied).";
      case DirectoryLayoutIssueKind.unreadable:
        return "Couldn't load saved layout for this folder.";
      case DirectoryLayoutIssueKind.corrupt:
        return "Couldn't load saved layout for this folder (file is damaged).";
      case DirectoryLayoutIssueKind.storageFallback:
        return "Couldn't store this folder's layout in the selected backend. Using the previous store.";
    }
  }

  bool get blocksLayoutIo => kind != DirectoryLayoutIssueKind.storageFallback;

  @override
  bool operator ==(Object other) =>
      other is DirectoryLayoutIssue && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(path, kind);
}
