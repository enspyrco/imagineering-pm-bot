/// User link queries — maps Signal UUIDs to Kan accounts.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing user link CRUD operations.
mixin UserLinkQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the user link for [signalUuid], or `null` if none.
  SignalUserLink? getUserLink(String signalUuid) {
    final rows = db.handle.select(
      'SELECT * FROM signal_user_links WHERE signal_uuid = ?',
      [signalUuid],
    );
    if (rows.isEmpty) return null;
    return _userLinkFromRow(rows.first);
  }

  /// Creates a new user link.
  void createUserLink({
    required String signalUuid,
    required String kanUserEmail,
    String? signalDisplayName,
    String? workspaceMemberPublicId,
    String? createdByUuid,
  }) {
    db.handle.execute(
      'INSERT INTO signal_user_links '
      '(signal_uuid, kan_user_email, signal_display_name, '
      'workspace_member_public_id, created_by_uuid) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        signalUuid,
        kanUserEmail,
        signalDisplayName,
        workspaceMemberPublicId,
        createdByUuid,
      ],
    );
  }

  /// Updates fields on the user link for [signalUuid].
  ///
  /// Only non-null parameters are applied.
  void updateUserLink(
    String signalUuid, {
    String? kanUserEmail,
    String? signalDisplayName,
    String? workspaceMemberPublicId,
  }) {
    final sets = <String>[];
    final params = <Object?>[];

    if (kanUserEmail != null) {
      sets.add('kan_user_email = ?');
      params.add(kanUserEmail);
    }
    if (signalDisplayName != null) {
      sets.add('signal_display_name = ?');
      params.add(signalDisplayName);
    }
    if (workspaceMemberPublicId != null) {
      sets.add('workspace_member_public_id = ?');
      params.add(workspaceMemberPublicId);
    }

    if (sets.isEmpty) return;

    params.add(signalUuid);
    db.handle.execute(
      'UPDATE signal_user_links SET ${sets.join(', ')} WHERE signal_uuid = ?',
      params,
    );
  }

  /// Deletes the user link for [signalUuid].
  void deleteUserLink(String signalUuid) {
    db.handle.execute(
      'DELETE FROM signal_user_links WHERE signal_uuid = ?',
      [signalUuid],
    );
  }

  /// Returns all user links.
  List<SignalUserLink> getAllUserLinks() {
    final rows = db.handle.select('SELECT * FROM signal_user_links');
    return [for (final row in rows) _userLinkFromRow(row)];
  }

  /// Returns the user link matching [email], or `null` if none.
  SignalUserLink? getUserLinkByEmail(String email) {
    final rows = db.handle.select(
      'SELECT * FROM signal_user_links WHERE kan_user_email = ?',
      [email],
    );
    if (rows.isEmpty) return null;
    return _userLinkFromRow(rows.first);
  }

  SignalUserLink _userLinkFromRow(Map<String, Object?> row) {
    return SignalUserLink(
      id: row['id']! as int,
      signalUuid: row['signal_uuid']! as String,
      signalDisplayName: row['signal_display_name'] as String?,
      kanUserEmail: row['kan_user_email']! as String,
      workspaceMemberPublicId: row['workspace_member_public_id'] as String?,
      createdAt: row['created_at']! as String,
      createdByUuid: row['created_by_uuid'] as String?,
    );
  }
}
