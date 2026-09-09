import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'layout_database.g.dart';

class DirectoryMetas extends Table {
  TextColumn get path => text()();
  TextColumn get placementJson => text()();
  TextColumn get version => text()();

  @override
  Set<Column<Object>> get primaryKey => {path};
}

class LayoutNodes extends Table {
  TextColumn get path => text()();
  TextColumn get name => text()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {path, name};
}

@DriftDatabase(tables: [DirectoryMetas, LayoutNodes])
class LayoutDatabase extends _$LayoutDatabase {
  LayoutDatabase(super.e);

  factory LayoutDatabase.file(File file) {
    return LayoutDatabase(NativeDatabase.createInBackground(file));
  }

  factory LayoutDatabase.memory() {
    return LayoutDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;
}
