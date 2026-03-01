/// OAuth token queries.
library;

import '../database.dart';

/// Mixin providing OAuth token CRUD operations.
mixin OAuthQueries {
  /// The database handle. Provided by the mixing-in class.
  BotDatabase get db;

  /// Returns the token value for [tokenType], or `null`.
  String? getOAuthToken(String tokenType) {
    final rows = db.handle.select(
      'SELECT token_value FROM oauth_tokens WHERE token_type = ?',
      [tokenType],
    );
    if (rows.isEmpty) return null;
    return rows.first['token_value'] as String;
  }

  /// Saves or updates an OAuth token.
  void saveOAuthToken(String tokenType, String tokenValue, {int? expiresAt}) {
    db.handle.execute(
      'INSERT INTO oauth_tokens (token_type, token_value, expires_at, updated_at) '
      "VALUES (?, ?, ?, datetime('now')) "
      'ON CONFLICT(token_type) DO UPDATE SET '
      'token_value = excluded.token_value, '
      'expires_at = excluded.expires_at, '
      "updated_at = datetime('now')",
      [tokenType, tokenValue, expiresAt],
    );
  }
}
