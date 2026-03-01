/// Calendar reminder queries — deduplication for event reminders.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing calendar reminder CRUD operations.
mixin CalendarQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns `true` if a reminder has already been sent for this
  /// event/group/window.
  bool hasCalendarReminderBeenSent(
    String eventUid,
    String signalGroupId,
    CalendarReminderWindow reminderWindow,
  ) {
    final rows = db.handle.select(
      'SELECT 1 FROM calendar_reminders '
      'WHERE event_uid = ? AND signal_group_id = ? AND reminder_window = ?',
      [eventUid, signalGroupId, reminderWindow.dbValue],
    );
    return rows.isNotEmpty;
  }

  /// Records a calendar reminder as sent (idempotent).
  void recordCalendarReminder(
    String eventUid,
    String signalGroupId,
    CalendarReminderWindow reminderWindow,
  ) {
    db.handle.execute(
      'INSERT OR IGNORE INTO calendar_reminders '
      '(event_uid, signal_group_id, reminder_window, sent_at) '
      "VALUES (?, ?, ?, datetime('now'))",
      [eventUid, signalGroupId, reminderWindow.dbValue],
    );
  }

  /// Deletes calendar reminders older than [olderThanDays] days.
  void cleanOldCalendarReminders({int olderThanDays = 7}) {
    db.handle.execute(
      "DELETE FROM calendar_reminders WHERE sent_at < datetime('now', ?)",
      ['-$olderThanDays days'],
    );
  }
}
