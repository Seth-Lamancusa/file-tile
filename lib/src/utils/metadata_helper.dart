import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'json_file_manager.dart';
import '../models/new_element_placement_config.dart';

class MetadataManager extends JsonFileManager {
  /// Name of the per-directory metadata file, as it appears on disk.
  static const String fileName = 'file-tile.json';

  /// Old name of the metadata file, from before the stitch-grid -> file-tile
  /// rebrand. Renamed to [fileName] in place on first access so existing
  /// layouts aren't lost.
  static const String legacyFileName = 'stitch-grid.json';

  late Map<String, dynamic> _data;

  MetadataManager(String directoryPath)
      : super(
          File(p.join(directoryPath, fileName)),
          legacyFile: File(p.join(directoryPath, legacyFileName)),
        );

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

    final data = decoded.cast<String, dynamic>();
    final layout = data['layout'];
    if (layout != null && layout is! Map) {
      throw FormatException('layout must be an object');
    }

    final config = data['newElementPlacementConfig'];
    if (config != null) {
      if (config is! Map) {
        throw FormatException('newElementPlacementConfig must be an object');
      }
      try {
        NewElementPlacementConfig.fromJson(config.cast<String, dynamic>());
      } on ArgumentError catch (e) {
        throw FormatException('Invalid newElementPlacementConfig: ${e.message}');
      }
    }

    return data;
  }

  @override
  Map<String, dynamic> getDefaultData() => {
        'layout': {},
        'newElementPlacementConfig': NewElementPlacementConfig.defaultConfig().toJson(),
        'version': '1.0'
      };

  Future<void> load() async {
    _data = await loadData();
  }

  Map<String, dynamic> get layout => (_data['layout'] as Map).cast<String, dynamic>();

  NewElementPlacementConfig get newElementPlacementConfig {
    final configData = _data['newElementPlacementConfig'];
    if (configData != null) {
      return NewElementPlacementConfig.fromJson((configData as Map).cast<String, dynamic>());
    }
    return NewElementPlacementConfig.defaultConfig();
  }

  Future<void> updateLayout(Map<String, dynamic> newLayout) async {
    _data = await updateAtomic((current) {
      current['layout'] = newLayout;
      return current;
    });
  }

  Future<void> updateNewElementPlacementConfig(NewElementPlacementConfig config) async {
    _data = await updateAtomic((current) {
      current['newElementPlacementConfig'] = config.toJson();
      return current;
    });
  }

  Future<void> removeNode(String nodeName) async {
    _data = await updateAtomic((current) {
      final layout = Map<String, dynamic>.from((current['layout'] as Map?) ?? {});
      layout.remove(nodeName);
      current['layout'] = layout;
      return current;
    });
  }

  Future<void> renameNode(String oldName, String newName) async {
    _data = await updateAtomic((current) {
      final layout = Map<String, dynamic>.from((current['layout'] as Map?) ?? {});
      if (layout.containsKey(oldName)) {
        layout[newName] = layout.remove(oldName);
      }
      current['layout'] = layout;
      return current;
    });
  }
}
