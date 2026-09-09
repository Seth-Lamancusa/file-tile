// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'layout_database.dart';

// ignore_for_file: type=lint
class $DirectoryMetasTable extends DirectoryMetas
    with TableInfo<$DirectoryMetasTable, DirectoryMeta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DirectoryMetasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _placementJsonMeta =
      const VerificationMeta('placementJson');
  @override
  late final GeneratedColumn<String> placementJson = GeneratedColumn<String>(
      'placement_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
      'version', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [path, placementJson, version];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'directory_metas';
  @override
  VerificationContext validateIntegrity(Insertable<DirectoryMeta> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('placement_json')) {
      context.handle(
          _placementJsonMeta,
          placementJson.isAcceptableOrUnknown(
              data['placement_json']!, _placementJsonMeta));
    } else if (isInserting) {
      context.missing(_placementJsonMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  DirectoryMeta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DirectoryMeta(
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      placementJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}placement_json'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}version'])!,
    );
  }

  @override
  $DirectoryMetasTable createAlias(String alias) {
    return $DirectoryMetasTable(attachedDatabase, alias);
  }
}

class DirectoryMeta extends DataClass implements Insertable<DirectoryMeta> {
  final String path;
  final String placementJson;
  final String version;
  const DirectoryMeta(
      {required this.path, required this.placementJson, required this.version});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['placement_json'] = Variable<String>(placementJson);
    map['version'] = Variable<String>(version);
    return map;
  }

  DirectoryMetasCompanion toCompanion(bool nullToAbsent) {
    return DirectoryMetasCompanion(
      path: Value(path),
      placementJson: Value(placementJson),
      version: Value(version),
    );
  }

  factory DirectoryMeta.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DirectoryMeta(
      path: serializer.fromJson<String>(json['path']),
      placementJson: serializer.fromJson<String>(json['placementJson']),
      version: serializer.fromJson<String>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'placementJson': serializer.toJson<String>(placementJson),
      'version': serializer.toJson<String>(version),
    };
  }

  DirectoryMeta copyWith(
          {String? path, String? placementJson, String? version}) =>
      DirectoryMeta(
        path: path ?? this.path,
        placementJson: placementJson ?? this.placementJson,
        version: version ?? this.version,
      );
  DirectoryMeta copyWithCompanion(DirectoryMetasCompanion data) {
    return DirectoryMeta(
      path: data.path.present ? data.path.value : this.path,
      placementJson: data.placementJson.present
          ? data.placementJson.value
          : this.placementJson,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DirectoryMeta(')
          ..write('path: $path, ')
          ..write('placementJson: $placementJson, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, placementJson, version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DirectoryMeta &&
          other.path == this.path &&
          other.placementJson == this.placementJson &&
          other.version == this.version);
}

class DirectoryMetasCompanion extends UpdateCompanion<DirectoryMeta> {
  final Value<String> path;
  final Value<String> placementJson;
  final Value<String> version;
  final Value<int> rowid;
  const DirectoryMetasCompanion({
    this.path = const Value.absent(),
    this.placementJson = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DirectoryMetasCompanion.insert({
    required String path,
    required String placementJson,
    required String version,
    this.rowid = const Value.absent(),
  })  : path = Value(path),
        placementJson = Value(placementJson),
        version = Value(version);
  static Insertable<DirectoryMeta> custom({
    Expression<String>? path,
    Expression<String>? placementJson,
    Expression<String>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (placementJson != null) 'placement_json': placementJson,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DirectoryMetasCompanion copyWith(
      {Value<String>? path,
      Value<String>? placementJson,
      Value<String>? version,
      Value<int>? rowid}) {
    return DirectoryMetasCompanion(
      path: path ?? this.path,
      placementJson: placementJson ?? this.placementJson,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (placementJson.present) {
      map['placement_json'] = Variable<String>(placementJson.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DirectoryMetasCompanion(')
          ..write('path: $path, ')
          ..write('placementJson: $placementJson, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LayoutNodesTable extends LayoutNodes
    with TableInfo<$LayoutNodesTable, LayoutNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LayoutNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [path, name, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'layout_nodes';
  @override
  VerificationContext validateIntegrity(Insertable<LayoutNode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path, name};
  @override
  LayoutNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LayoutNode(
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
    );
  }

  @override
  $LayoutNodesTable createAlias(String alias) {
    return $LayoutNodesTable(attachedDatabase, alias);
  }
}

class LayoutNode extends DataClass implements Insertable<LayoutNode> {
  final String path;
  final String name;
  final String payload;
  const LayoutNode(
      {required this.path, required this.name, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['name'] = Variable<String>(name);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  LayoutNodesCompanion toCompanion(bool nullToAbsent) {
    return LayoutNodesCompanion(
      path: Value(path),
      name: Value(name),
      payload: Value(payload),
    );
  }

  factory LayoutNode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LayoutNode(
      path: serializer.fromJson<String>(json['path']),
      name: serializer.fromJson<String>(json['name']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'name': serializer.toJson<String>(name),
      'payload': serializer.toJson<String>(payload),
    };
  }

  LayoutNode copyWith({String? path, String? name, String? payload}) =>
      LayoutNode(
        path: path ?? this.path,
        name: name ?? this.name,
        payload: payload ?? this.payload,
      );
  LayoutNode copyWithCompanion(LayoutNodesCompanion data) {
    return LayoutNode(
      path: data.path.present ? data.path.value : this.path,
      name: data.name.present ? data.name.value : this.name,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LayoutNode(')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(path, name, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LayoutNode &&
          other.path == this.path &&
          other.name == this.name &&
          other.payload == this.payload);
}

class LayoutNodesCompanion extends UpdateCompanion<LayoutNode> {
  final Value<String> path;
  final Value<String> name;
  final Value<String> payload;
  final Value<int> rowid;
  const LayoutNodesCompanion({
    this.path = const Value.absent(),
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LayoutNodesCompanion.insert({
    required String path,
    required String name,
    required String payload,
    this.rowid = const Value.absent(),
  })  : path = Value(path),
        name = Value(name),
        payload = Value(payload);
  static Insertable<LayoutNode> custom({
    Expression<String>? path,
    Expression<String>? name,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (name != null) 'name': name,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LayoutNodesCompanion copyWith(
      {Value<String>? path,
      Value<String>? name,
      Value<String>? payload,
      Value<int>? rowid}) {
    return LayoutNodesCompanion(
      path: path ?? this.path,
      name: name ?? this.name,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LayoutNodesCompanion(')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LayoutDatabase extends GeneratedDatabase {
  _$LayoutDatabase(QueryExecutor e) : super(e);
  $LayoutDatabaseManager get managers => $LayoutDatabaseManager(this);
  late final $DirectoryMetasTable directoryMetas = $DirectoryMetasTable(this);
  late final $LayoutNodesTable layoutNodes = $LayoutNodesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [directoryMetas, layoutNodes];
}

typedef $$DirectoryMetasTableCreateCompanionBuilder = DirectoryMetasCompanion
    Function({
  required String path,
  required String placementJson,
  required String version,
  Value<int> rowid,
});
typedef $$DirectoryMetasTableUpdateCompanionBuilder = DirectoryMetasCompanion
    Function({
  Value<String> path,
  Value<String> placementJson,
  Value<String> version,
  Value<int> rowid,
});

class $$DirectoryMetasTableFilterComposer
    extends Composer<_$LayoutDatabase, $DirectoryMetasTable> {
  $$DirectoryMetasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get placementJson => $composableBuilder(
      column: $table.placementJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));
}

class $$DirectoryMetasTableOrderingComposer
    extends Composer<_$LayoutDatabase, $DirectoryMetasTable> {
  $$DirectoryMetasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get placementJson => $composableBuilder(
      column: $table.placementJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));
}

class $$DirectoryMetasTableAnnotationComposer
    extends Composer<_$LayoutDatabase, $DirectoryMetasTable> {
  $$DirectoryMetasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get placementJson => $composableBuilder(
      column: $table.placementJson, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$DirectoryMetasTableTableManager extends RootTableManager<
    _$LayoutDatabase,
    $DirectoryMetasTable,
    DirectoryMeta,
    $$DirectoryMetasTableFilterComposer,
    $$DirectoryMetasTableOrderingComposer,
    $$DirectoryMetasTableAnnotationComposer,
    $$DirectoryMetasTableCreateCompanionBuilder,
    $$DirectoryMetasTableUpdateCompanionBuilder,
    (
      DirectoryMeta,
      BaseReferences<_$LayoutDatabase, $DirectoryMetasTable, DirectoryMeta>
    ),
    DirectoryMeta,
    PrefetchHooks Function()> {
  $$DirectoryMetasTableTableManager(
      _$LayoutDatabase db, $DirectoryMetasTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DirectoryMetasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DirectoryMetasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DirectoryMetasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> path = const Value.absent(),
            Value<String> placementJson = const Value.absent(),
            Value<String> version = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DirectoryMetasCompanion(
            path: path,
            placementJson: placementJson,
            version: version,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String path,
            required String placementJson,
            required String version,
            Value<int> rowid = const Value.absent(),
          }) =>
              DirectoryMetasCompanion.insert(
            path: path,
            placementJson: placementJson,
            version: version,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$DirectoryMetasTable, DirectoryMeta>(table),
                    BaseReferences<_$LayoutDatabase, $DirectoryMetasTable,
                        DirectoryMeta>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DirectoryMetasTableProcessedTableManager = ProcessedTableManager<
    _$LayoutDatabase,
    $DirectoryMetasTable,
    DirectoryMeta,
    $$DirectoryMetasTableFilterComposer,
    $$DirectoryMetasTableOrderingComposer,
    $$DirectoryMetasTableAnnotationComposer,
    $$DirectoryMetasTableCreateCompanionBuilder,
    $$DirectoryMetasTableUpdateCompanionBuilder,
    (
      DirectoryMeta,
      BaseReferences<_$LayoutDatabase, $DirectoryMetasTable, DirectoryMeta>
    ),
    DirectoryMeta,
    PrefetchHooks Function()>;
typedef $$LayoutNodesTableCreateCompanionBuilder = LayoutNodesCompanion
    Function({
  required String path,
  required String name,
  required String payload,
  Value<int> rowid,
});
typedef $$LayoutNodesTableUpdateCompanionBuilder = LayoutNodesCompanion
    Function({
  Value<String> path,
  Value<String> name,
  Value<String> payload,
  Value<int> rowid,
});

class $$LayoutNodesTableFilterComposer
    extends Composer<_$LayoutDatabase, $LayoutNodesTable> {
  $$LayoutNodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$LayoutNodesTableOrderingComposer
    extends Composer<_$LayoutDatabase, $LayoutNodesTable> {
  $$LayoutNodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$LayoutNodesTableAnnotationComposer
    extends Composer<_$LayoutDatabase, $LayoutNodesTable> {
  $$LayoutNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$LayoutNodesTableTableManager extends RootTableManager<
    _$LayoutDatabase,
    $LayoutNodesTable,
    LayoutNode,
    $$LayoutNodesTableFilterComposer,
    $$LayoutNodesTableOrderingComposer,
    $$LayoutNodesTableAnnotationComposer,
    $$LayoutNodesTableCreateCompanionBuilder,
    $$LayoutNodesTableUpdateCompanionBuilder,
    (
      LayoutNode,
      BaseReferences<_$LayoutDatabase, $LayoutNodesTable, LayoutNode>
    ),
    LayoutNode,
    PrefetchHooks Function()> {
  $$LayoutNodesTableTableManager(_$LayoutDatabase db, $LayoutNodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LayoutNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LayoutNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LayoutNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> path = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LayoutNodesCompanion(
            path: path,
            name: name,
            payload: payload,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String path,
            required String name,
            required String payload,
            Value<int> rowid = const Value.absent(),
          }) =>
              LayoutNodesCompanion.insert(
            path: path,
            name: name,
            payload: payload,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LayoutNodesTable, LayoutNode>(table),
                    BaseReferences<_$LayoutDatabase, $LayoutNodesTable,
                        LayoutNode>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LayoutNodesTableProcessedTableManager = ProcessedTableManager<
    _$LayoutDatabase,
    $LayoutNodesTable,
    LayoutNode,
    $$LayoutNodesTableFilterComposer,
    $$LayoutNodesTableOrderingComposer,
    $$LayoutNodesTableAnnotationComposer,
    $$LayoutNodesTableCreateCompanionBuilder,
    $$LayoutNodesTableUpdateCompanionBuilder,
    (
      LayoutNode,
      BaseReferences<_$LayoutDatabase, $LayoutNodesTable, LayoutNode>
    ),
    LayoutNode,
    PrefetchHooks Function()>;

class $LayoutDatabaseManager {
  final _$LayoutDatabase _db;
  $LayoutDatabaseManager(this._db);
  $$DirectoryMetasTableTableManager get directoryMetas =>
      $$DirectoryMetasTableTableManager(_db, _db.directoryMetas);
  $$LayoutNodesTableTableManager get layoutNodes =>
      $$LayoutNodesTableTableManager(_db, _db.layoutNodes);
}
