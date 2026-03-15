/// Card reminder queries — tracks sent reminders to avoid spamming.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing sent-reminder CRUD operations.
mixin ReminderQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the last reminder for a card/group/type combo, or `null`.
  SentReminder? getLastReminder(
    String cardPublicId,
    String groupId, {
    ReminderType reminderType = ReminderType.overdue,
  }) {
    final rows = db.handle.select(
      'SELECT * FROM sent_reminders '
      'WHERE card_public_id = ? AND group_id = ? AND reminder_type = ?',
      [cardPublicId, groupId, reminderType.dbValue],
    );
    if (rows.isEmpty) return null;
    return _reminderFromRow(rows.first);
  }

  /// Records or updates a reminder for the given card/group/type.
  void upsertReminder(
    String cardPublicId,
    String groupId, {
    ReminderType reminderType = ReminderType.overdue,
  }) {
    db.handle.execute(
      'INSERT INTO sent_reminders '
      '(card_public_id, group_id, reminder_type, last_reminder_at) '
      "VALUES (?, ?, ?, datetime('now')) "
      'ON CONFLICT(card_public_id, group_id, reminder_type) DO UPDATE SET '
      "last_reminder_at = datetime('now')",
      [cardPublicId, groupId, reminderType.dbValue],
    );
  }

  /// Deletes reminders older than [olderThanDays] days.
  void cleanOldReminders({int olderThanDays = 7}) {
    db.handle.execute(
      'DELETE FROM sent_reminders '
      "WHERE last_reminder_at < datetime('now', ?)",
      ['-$olderThanDays days'],
    );
  }

  SentReminder _reminderFromRow(Map<String, Object?> row) {
    return SentReminder(
      id: row['id']! as int,
      cardPublicId: row['card_public_id']! as String,
      groupId: row['group_id']! as String,
      reminderType: ReminderType.fromDb(row['reminder_type']! as String),
      lastReminderAt: row['last_reminder_at']! as String,
    );
  }
}
