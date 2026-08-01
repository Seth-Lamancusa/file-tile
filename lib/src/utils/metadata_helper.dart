import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'json_file_manager.dart';

class MetadataManager extends JsonFileManager {
  late Map<String, dynamic> _data;

  MetadataManager(String directoryPath)
      : super(File(p.join(directoryPath, 'stitch-grid.json')));

  @override
  Map<String, dynamic> validateAndLoad(String jsonString) {
    if (jsonString.isEmpty) {
      throw FormatException('Empty metadata file');
    }

    final trimmed = jsonString.trim();
    if (!trimmed.startsWith('{')) {
      throw FormatException('Invalid metadata: does not start with {');
    }

    final decoded = json.decode(trimmed);
    if (decoded is! Map) {
      throw FormatException('Metadata root must be a JSON object');
    }

    final data = (decoded as Map).cast<String, dynamic>();
    final layout = data['layout'];
    if (layout != null && layout is! Map) {
      throw FormatException('layout must be an object');
    }

    return data;
  }

  @override
  Map<String, dynamic> getDefaultData() => {'layout': {}, 'version': '1.0'};

  Future<void> load() async {
    _data = await loadData();
  }

  Map<String, dynamic> get layout => (_data['layout'] as Map).cast<String, dynamic>();

  Future<void> updateLayout(Map<String, dynamic> newLayout) async {
    _data['layout'] = newLayout;
    await save(_data);
  }

  Future<void> removeNode(String nodeName) async {
    layout.remove(nodeName);
    await save(_data);
  }

  Future<void> renameNode(String oldName, String newName) async {
    if (layout.containsKey(oldName)) {
      layout[newName] = layout.remove(oldName);
      await save(_data);
    }
  }
}
