import 'package:path/path.dart' as p;

/// Returns [name] if it is free, otherwise `stem (copy).ext`, `stem (copy 2).ext`, …
String uniqueCopyName(String name, Set<String> taken) {
  if (!taken.contains(name)) return name;
  final ext = p.extension(name);
  var stem = name.substring(0, name.length - ext.length);
  if (stem.isEmpty) stem = name;
  var i = 1;
  while (true) {
    final candidate = i == 1 ? '$stem (copy)$ext' : '$stem (copy $i)$ext';
    if (!taken.contains(candidate)) return candidate;
    i++;
  }
}
