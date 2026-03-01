/// Default board config queries — default board/list for card creation.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing default board config CRUD operations.
mixin BoardConfigQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the default board config for [signalGroupId], or `null`.
  DefaultBoardConfigRecord? getDefaultBoardConfig(String signalGroupId) {
    final rows = db.handle.select(
      'SELECT * FROM default_board_config WHERE signal_group_id = ?',
      [signalGroupId],
    );
    if (rows.isEmpty) return null;
    return _boardConfigFromRow(rows.first);
  }

  /// Inserts or updates the default board config for a group.
  void upsertDefaultBoardConfig({
    required String signalGroupId,
    required String boardPublicId,
    required String listPublicId,
    required String boardName,
    required String listName,
  }) {
    db.handle.execute(
      'INSERT INTO default_board_config '
      '(signal_group_id, board_public_id, list_public_id, board_name, list_name) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(signal_group_id) DO UPDATE SET '
      'board_public_id = excluded.board_public_id, '
      'list_public_id = excluded.list_public_id, '
      'board_name = excluded.board_name, '
      'list_name = excluded.list_name, '
      "updated_at = datetime('now')",
      [signalGroupId, boardPublicId, listPublicId, boardName, listName],
    );
  }

  DefaultBoardConfigRecord _boardConfigFromRow(Map<String, Object?> row) {
    return DefaultBoardConfigRecord(
      id: row['id']! as int,
      signalGroupId: row['signal_group_id']! as String,
      boardPublicId: row['board_public_id']! as String,
      listPublicId: row['list_public_id']! as String,
      boardName: row['board_name']! as String,
      listName: row['list_name']! as String,
      updatedAt: row['updated_at']! as String,
    );
  }
}
