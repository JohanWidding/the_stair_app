import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;
  Database get raw => _db;

  static const _fileName = 'the_stair_app.db';
  static const _version  = 6;

  static Future<void> _enableForeignKeys(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  floor_height_mm REAL NOT NULL DEFAULT 2600
)
''');
    await db.execute('''
CREATE TABLE levels (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  elevation_mm REAL NOT NULL DEFAULT 0,
  ordinal INTEGER NOT NULL DEFAULT 0,
  is_auto_named INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
)
''');
  }

  static Future<AppDatabase> open() async {
    final dir  = await getDatabasesPath();
    final path = p.join(dir, _fileName);
    final db   = await openDatabase(
      path,
      version: _version,
      onOpen: _enableForeignKeys,
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1-v5 contained the old Staircase model tables; those remain on disk
        // but are no longer used.  v6 adds nothing new.
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> deleteFile() async {
    final dir  = await getDatabasesPath();
    final path = p.join(dir, _fileName);
    await deleteDatabase(path);
  }
}
