/// User link queries — maps user IDs to Kan accounts.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing user link CRUD operations.
mixin UserLinkQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the user link for [userId], or `null` if none.
  UserLink? getUserLink(String userId) {
    final rows = db.handle.select(
      'SELECT * FROM user_links WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return null;
    return _userLinkFromRow(rows.first);
  }

  /// Creates a new user link.
  void createUserLink({
    required String userId,
    required String kanUserEmail,
    String? displayName,
    String? workspaceMemberPublicId,
    String? createdByUuid,
  }) {
    db.handle.execute(
      'INSERT INTO user_links '
      '(user_id, kan_user_email, display_name, '
      'workspace_member_public_id, created_by_uuid) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        userId,
        kanUserEmail,
        displayName,
        workspaceMemberPublicId,
        createdByUuid,
      ],
    );
  }

  /// Updates fields on the user link for [userId].
  ///
  /// Only non-null parameters are applied.
  void updateUserLink(
    String userId, {
    String? kanUserEmail,
    String? displayName,
    String? workspaceMemberPublicId,
  }) {
    final sets = <String>[];
    final params = <Object?>[];

    if (kanUserEmail != null) {
      sets.add('kan_user_email = ?');
      params.add(kanUserEmail);
    }
    if (displayName != null) {
      sets.add('display_name = ?');
      params.add(displayName);
    }
    if (workspaceMemberPublicId != null) {
      sets.add('workspace_member_public_id = ?');
      params.add(workspaceMemberPublicId);
    }

    if (sets.isEmpty) return;

    params.add(userId);
    db.handle.execute(
      'UPDATE user_links SET ${sets.join(', ')} WHERE user_id = ?',
      params,
    );
  }

  /// Deletes the user link for [userId].
  void deleteUserLink(String userId) {
    db.handle.execute(
      'DELETE FROM user_links WHERE user_id = ?',
      [userId],
    );
  }

  /// Returns all user links.
  List<UserLink> getAllUserLinks() {
    final rows = db.handle.select('SELECT * FROM user_links');
    return [for (final row in rows) _userLinkFromRow(row)];
  }

  /// Returns the user link matching [email], or `null` if none.
  UserLink? getUserLinkByEmail(String email) {
    final rows = db.handle.select(
      'SELECT * FROM user_links WHERE kan_user_email = ?',
      [email],
    );
    if (rows.isEmpty) return null;
    return _userLinkFromRow(rows.first);
  }

  UserLink _userLinkFromRow(Map<String, Object?> row) {
    return UserLink(
      id: row['id']! as int,
      userId: row['user_id']! as String,
      displayName: row['display_name'] as String?,
      kanUserEmail: row['kan_user_email']! as String,
      workspaceMemberPublicId: row['workspace_member_public_id'] as String?,
      createdAt: row['created_at']! as String,
      createdByUuid: row['created_by_uuid'] as String?,
    );
  }
}
