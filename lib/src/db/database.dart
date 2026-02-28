import 'package:sqlite3/sqlite3.dart';

/// SQLite database wrapper for Figment.
///
/// Manages the connection and schema initialization. Use [BotDatabase.open]
/// for file-based persistence or [BotDatabase.inMemory] for tests.
class BotDatabase {
  BotDatabase._(this._db) {
    _createSchema();
  }

  /// Opens a file-backed SQLite database at [path], creating it if needed.
  factory BotDatabase.open(String path) {
    final db = sqlite3.open(path);
    return BotDatabase._(db);
  }

  /// Opens an in-memory database — ideal for tests.
  factory BotDatabase.inMemory() {
    final db = sqlite3.openInMemory();
    return BotDatabase._(db);
  }

  final Database _db;

  /// The underlying sqlite3 [Database] handle for direct queries.
  Database get handle => _db;

  /// Returns all user-created table names in the database.
  List<String> tableNames() {
    final result = _db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    return [for (final row in result) row['name'] as String];
  }

  /// Returns all index names in the database.
  List<String> indexNames() {
    final result = _db.select(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    return [for (final row in result) row['name'] as String];
  }

  /// Closes the database connection.
  void close() {
    _db.dispose();
  }

  void _createSchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        chat_id    TEXT PRIMARY KEY,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        last_activity TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id     TEXT    NOT NULL REFERENCES conversations(chat_id),
        role        TEXT    NOT NULL CHECK (role IN ('user', 'assistant')),
        content     TEXT    NOT NULL,
        sender_uuid TEXT,
        sender_name TEXT,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_chat_id
      ON messages(chat_id)
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_created_at
      ON messages(created_at)
    ''');
  }
}
