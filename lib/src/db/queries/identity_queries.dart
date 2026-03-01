/// Bot identity queries — name, pronouns, tone.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing bot identity CRUD operations.
mixin IdentityQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the most recently chosen bot identity, or `null`.
  BotIdentityRecord? getBotIdentity() {
    final rows = db.handle.select(
      'SELECT * FROM bot_identity ORDER BY chosen_at DESC, id DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return _botIdentityFromRow(rows.first);
  }

  /// Saves a new bot identity record.
  void saveBotIdentity({
    required String name,
    required String pronouns,
    required String tone,
    String? toneDescription,
    String? chosenInGroupId,
  }) {
    db.handle.execute(
      'INSERT INTO bot_identity '
      '(name, pronouns, tone, tone_description, chosen_in_group_id) '
      'VALUES (?, ?, ?, ?, ?)',
      [name, pronouns, tone, toneDescription, chosenInGroupId],
    );
  }

  BotIdentityRecord _botIdentityFromRow(Map<String, Object?> row) {
    return BotIdentityRecord(
      id: row['id']! as int,
      name: row['name']! as String,
      pronouns: row['pronouns']! as String,
      tone: row['tone']! as String,
      toneDescription: row['tone_description'] as String?,
      chosenAt: row['chosen_at']! as String,
      chosenInGroupId: row['chosen_in_group_id'] as String?,
    );
  }
}
