import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../services/storage_service.dart';

/// SQLite Database manager with Write-Ahead Logging (WAL) and foreign key enforcement.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final docsDir = await StorageService.instance.documentsDir;
    final dbPath = p.join(docsDir.path, 'offline_image.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        try {
          await db.execute('PRAGMA foreign_keys = ON;');
        } catch (_) {}
        try {
          // On Android SQLite, PRAGMA journal_mode returns a result set,
          // so rawQuery() must be used instead of execute().
          await db.rawQuery('PRAGMA journal_mode = WAL;');
        } catch (_) {}
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            prompt TEXT NOT NULL,
            negative_prompt TEXT,
            image_path TEXT,
            status TEXT NOT NULL,
            step_progress INTEGER NOT NULL DEFAULT 0,
            total_steps INTEGER NOT NULL DEFAULT 20,
            seed INTEGER NOT NULL DEFAULT -1,
            cfg_scale REAL NOT NULL DEFAULT 7.0,
            duration_seconds REAL,
            error_message TEXT,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (chat_id) REFERENCES chats (id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE INDEX idx_messages_chat_id ON messages (chat_id);
        ''');
      },
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
