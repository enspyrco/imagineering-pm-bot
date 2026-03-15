/// Workspace link queries — maps groups to Kan workspaces.
library;

import '../database.dart';
import '../schema.dart';

/// Mixin providing workspace link CRUD operations.
mixin WorkspaceQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the workspace link for [groupId], or `null` if none.
  WorkspaceLink? getWorkspaceLink(String groupId) {
    final rows = db.handle.select(
      'SELECT * FROM workspace_links WHERE group_id = ?',
      [groupId],
    );
    if (rows.isEmpty) return null;
    return _workspaceLinkFromRow(rows.first);
  }

  /// Creates a new workspace link.
  void createWorkspaceLink({
    required String groupId,
    required String workspacePublicId,
    required String workspaceName,
    required String createdByUuid,
  }) {
    db.handle.execute(
      'INSERT INTO workspace_links '
      '(group_id, workspace_public_id, workspace_name, created_by_uuid) '
      'VALUES (?, ?, ?, ?)',
      [groupId, workspacePublicId, workspaceName, createdByUuid],
    );
  }

  /// Deletes the workspace link for [groupId].
  void deleteWorkspaceLink(String groupId) {
    db.handle.execute(
      'DELETE FROM workspace_links WHERE group_id = ?',
      [groupId],
    );
  }

  /// Returns all workspace links.
  List<WorkspaceLink> getAllWorkspaceLinks() {
    final rows = db.handle.select('SELECT * FROM workspace_links');
    return [for (final row in rows) _workspaceLinkFromRow(row)];
  }

  WorkspaceLink _workspaceLinkFromRow(Map<String, Object?> row) {
    return WorkspaceLink(
      id: row['id']! as int,
      groupId: row['group_id']! as String,
      workspacePublicId: row['workspace_public_id']! as String,
      workspaceName: row['workspace_name']! as String,
      createdAt: row['created_at']! as String,
      createdByUuid: row['created_by_uuid']! as String,
    );
  }
}
