/// Sliding-window conversation history per chat.
///
/// Keeps the last [maxMessages] messages per chat ID, evicting oldest
/// user/assistant pairs when the window overflows. Entries expire after
/// [ttl] of inactivity to avoid unbounded memory growth.
library;

/// Role of a message in the conversation.
enum MessageRole { user, assistant }

/// A single message in the conversation history.
class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final MessageRole role;
  final String content;
}

class _ChatEntry {
  _ChatEntry({required this.messages, required this.lastActivity});

  final List<ChatMessage> messages;
  DateTime lastActivity;
}

/// In-memory conversation history with sliding window and TTL expiry.
class ConversationHistory {
  ConversationHistory({
    this.maxMessages = 20,
    this.ttl = const Duration(minutes: 30),
  });

  final int maxMessages;
  final Duration ttl;
  final Map<String, _ChatEntry> _histories = {};

  List<ChatMessage> getHistory(String chatId) {
    final entry = _histories[chatId];
    if (entry == null) return [];
    if (_isExpired(entry)) {
      _histories.remove(chatId);
      return [];
    }
    return List.unmodifiable(entry.messages);
  }

  void appendToHistory(
    String chatId,
    ChatMessage userMessage,
    ChatMessage assistantMessage,
  ) {
    final now = DateTime.now();
    var entry = _histories[chatId];
    if (entry == null || _isExpired(entry)) {
      entry = _ChatEntry(messages: [], lastActivity: now);
    }
    entry.messages.add(userMessage);
    entry.messages.add(assistantMessage);
    entry.lastActivity = now;

    while (entry.messages.length > maxMessages) {
      entry.messages.removeAt(0);
      if (entry.messages.isNotEmpty) {
        entry.messages.removeAt(0);
      }
    }
    _histories[chatId] = entry;
  }

  void clearHistory(String chatId) {
    _histories.remove(chatId);
  }

  void evictStale() {
    final now = DateTime.now();
    _histories.removeWhere(
      (_, entry) => now.difference(entry.lastActivity) > ttl,
    );
  }

  bool _isExpired(_ChatEntry entry) {
    return DateTime.now().difference(entry.lastActivity) > ttl;
  }
}
