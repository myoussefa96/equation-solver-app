import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sf;
import 'package:sqflite_common/sqlite_api.dart';

class AppDatabase {
  AppDatabase._(this.raw);

  static const int schemaVersion = 1;

  final Database raw;

  /// Open the on-device app database. Used by the running Flutter app.
  static Future<AppDatabase> openApp() async {
    final dir = await sf.getDatabasesPath();
    final path = p.join(dir, 'equation_solver.db');
    final db = await sf.openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
    return AppDatabase._(db);
  }

  /// Open an in-memory database — used by tests.
  static Future<AppDatabase> openInMemory({
    required DatabaseFactory databaseFactory,
  }) async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    for (final stmt in _schema) {
      await db.execute(stmt);
    }
  }

  Future<void> close() => raw.close();

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      raw.transaction(action);
}

const List<String> _schema = [
  '''
  CREATE TABLE folders (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
  )
  ''',
  '''
  CREATE TABLE entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id   INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
  )
  ''',
  '''
  CREATE TABLE equations (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    output_var  TEXT    NOT NULL,
    ast_json    TEXT    NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    UNIQUE(entry_id, output_var)
  )
  ''',
  '''
  CREATE TABLE variable_meta (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id      INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    identifier    TEXT    NOT NULL,
    display_label TEXT    NOT NULL,
    unit          TEXT,
    role          TEXT    NOT NULL CHECK (role IN ('input','intermediate','output')),
    is_final      INTEGER NOT NULL DEFAULT 0,
    last_value    REAL,
    UNIQUE(entry_id, identifier)
  )
  ''',
  '''
  CREATE TABLE solve_history (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id     INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    inputs_json  TEXT    NOT NULL,
    outputs_json TEXT    NOT NULL,
    solved_at    TEXT    NOT NULL
  )
  ''',
];
