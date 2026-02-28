import 'package:imagineering_pm_bot/src/agent/conversation_history.dart';
import 'package:test/test.dart';

void main() {
  late ConversationHistory history;

  setUp(() {
    history = ConversationHistory(maxMessages: 6, ttl: const Duration(minutes: 30));
  });

  group('ConversationHistory', () {
    test('returns empty list for new chat', () {
      expect(history.getHistory('new'), isEmpty);
    });

    test('appends and retrieves messages', () {
      history.appendToHistory('c1',
          const ChatMessage(role: MessageRole.user, content: 'Hello'),
          const ChatMessage(role: MessageRole.assistant, content: 'Hi!'));
      final msgs = history.getHistory('c1');
      expect(msgs, hasLength(2));
      expect(msgs[0].role, equals(MessageRole.user));
      expect(msgs[1].content, equals('Hi!'));
    });

    test('enforces sliding window', () {
      for (var i = 0; i < 4; i++) {
        history.appendToHistory('c1',
            ChatMessage(role: MessageRole.user, content: 'msg $i'),
            ChatMessage(role: MessageRole.assistant, content: 'reply $i'));
      }
      final msgs = history.getHistory('c1');
      expect(msgs.length, lessThanOrEqualTo(6));
      expect(msgs.first.content, equals('msg 1'));
    });

    test('expires history after TTL', () {
      final short = ConversationHistory(maxMessages: 20, ttl: Duration.zero);
      short.appendToHistory('c1',
          const ChatMessage(role: MessageRole.user, content: 'Hello'),
          const ChatMessage(role: MessageRole.assistant, content: 'Hi'));
      expect(short.getHistory('c1'), isEmpty);
    });

    test('clearHistory removes messages', () {
      history.appendToHistory('c1',
          const ChatMessage(role: MessageRole.user, content: 'Hello'),
          const ChatMessage(role: MessageRole.assistant, content: 'Hi'));
      history.clearHistory('c1');
      expect(history.getHistory('c1'), isEmpty);
    });

    test('isolates history between chats', () {
      history.appendToHistory('a',
          const ChatMessage(role: MessageRole.user, content: 'A'),
          const ChatMessage(role: MessageRole.assistant, content: 'A reply'));
      history.appendToHistory('b',
          const ChatMessage(role: MessageRole.user, content: 'B'),
          const ChatMessage(role: MessageRole.assistant, content: 'B reply'));
      expect(history.getHistory('a'), hasLength(2));
      expect(history.getHistory('b'), hasLength(2));
      expect(history.getHistory('a').first.content, equals('A'));
      expect(history.getHistory('b').first.content, equals('B'));
    });
  });
}
