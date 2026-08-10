import 'dart:convert';
import 'dart:io';
import 'json_file_manager.dart';

class ConfigManager extends JsonFileManager {
  late Map<String, dynamic> _data;

  ConfigManager(File configFile, {File? legacyFile}) : super(configFile, legacyFile: legacyFile);

  @override
  Map<String, dynamic> validateAndLoad(String jsonString) {
    if (jsonString.isEmpty) {
      throw FormatException('Empty config file');
    }

    final trimmed = jsonString.trim();
    final decoded = json.decode(trimmed);

    if (decoded is! Map) {
      throw FormatException('Config root must be a JSON object');
    }

    return decoded.cast<String, dynamic>();
  }

  @override
  Map<String, dynamic> getDefaultData() => {};

  Future<void> load() async {
    _data = await loadData();
  }

  Map<String, dynamic> get data => _data;

  Future<void> update(Map<String, dynamic> Function(Map<String, dynamic>) updateFn) async {
    _data = await updateAtomic(updateFn);
  }
}
