/// Where per-directory layout metadata is stored.
enum MetadataBackend {
  json,
  sqlite;

  static const configKey = 'metadata_backend';

  static MetadataBackend fromConfig(Object? value) {
    return value == sqlite.configValue ? sqlite : json;
  }

  String get configValue => name;
}
