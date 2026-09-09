import 'package:path/path.dart' as p;

/// Canonical key for a visited directory in layout storage.
///
/// Absolute, normalized, no trailing separator (except a filesystem root).
/// Does not resolve symlinks.
String layoutDirectoryKey(String path) {
  var normalized = p.normalize(p.isAbsolute(path) ? path : p.absolute(path));
  if (normalized.length > 1 &&
      (normalized.endsWith(p.separator) || normalized.endsWith('/'))) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
