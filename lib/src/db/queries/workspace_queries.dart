/// Workspace link queries — maps Signal groups to Kan workspaces.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing workspace link CRUD operations.
mixin WorkspaceQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the workspace link for [signalGroupId], or `null` if none.
  SignalWorkspaceLink? getWorkspaceLink(String signalGroupId) {
    final rows = db.handle.select(
      'SELECT * FROM signal_workspace_links WHERE signal_group_id = ?',
      [signalGroupId],
    );
    if (rows.isEmpty) return null;
    return _workspaceLinkFromRow(rows.first);
  }

  /// Creates a new workspace link.
  void createWorkspaceLink({
    required String signalGroupId,
    required String workspacePublicId,
    required String workspaceName,
    required String createdByUuid,
  }) {
    db.handle.execute(
      'INSERT INTO signal_workspace_links '
      '(signal_group_id, workspace_public_id, workspace_name, created_by_uuid) '
      'VALUES (?, ?, ?, ?)',
      [signalGroupId, workspacePublicId, workspaceName, createdByUuid],
    );
  }

  /// Deletes the workspace link for [signalGroupId].
  void deleteWorkspaceLink(String signalGroupId) {
    db.handle.execute(
      'DELETE FROM signal_workspace_links WHERE signal_group_id = ?',
      [signalGroupId],
    );
  }

  /// Returns all workspace links.
  List<SignalWorkspaceLink> getAllWorkspaceLinks() {
    final rows = db.handle.select('SELECT * FROM signal_workspace_links');
    return [for (final row in rows) _workspaceLinkFromRow(row)];
  }

  SignalWorkspaceLink _workspaceLinkFromRow(Map<String, Object?> row) {
    return SignalWorkspaceLink(
      id: row['id']! as int,
      signalGroupId: row['signal_group_id']! as String,
      workspacePublicId: row['workspace_public_id']! as String,
      workspaceName: row['workspace_name']! as String,
      createdAt: row['created_at']! as String,
      createdByUuid: row['created_by_uuid']! as String,
    );
  }
}
