/// Enough to put a trashed file or folder back at [originalPath].
class TrashToken {
  final String originalPath;
  final String trashedPath;
  final String infoPath;

  const TrashToken({
    required this.originalPath,
    required this.trashedPath,
    required this.infoPath,
  });
}
