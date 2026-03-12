import 'dart:convert';

import 'package:dreamfinder/src/agent/tool_registry.dart';
import 'package:dreamfinder/src/memory/embedding_client.dart';
import 'package:dreamfinder/src/memory/embedding_pipeline.dart';
import 'package:dreamfinder/src/memory/memory_record.dart';
import 'package:dreamfinder/src/tools/memory_tools.dart';
import 'package:test/test.dart';

/// Fake [EmbeddingPipeline] that captures queue() calls for verification.
class _FakePipeline extends EmbeddingPipeline {
  _FakePipeline()
      : super(client: _NullEmbeddingClient(), queries: _NullQueries());

  final List<_QueueCall> calls = [];

  @override
  void queue({
    required String chatId,
    required String userText,
    required String assistantText,
    String? senderUuid,
    String? senderName,
    MemoryVisibility visibility = MemoryVisibility.sameChat,
  }) {
    calls.add(_QueueCall(
      chatId: chatId,
      userText: userText,
      assistantText: assistantText,
      senderUuid: senderUuid,
      senderName: senderName,
      visibility: visibility,
    ));
  }
}

class _QueueCall {
  const _QueueCall({
    required this.chatId,
    required this.userText,
    required this.assistantText,
    this.senderUuid,
    this.senderName,
    required this.visibility,
  });

  final String chatId;
  final String userText;
  final String assistantText;
  final String? senderUuid;
  final String? senderName;
  final MemoryVisibility visibility;
}

class _NullEmbeddingClient implements EmbeddingClient {
  @override
  int get dimensions => 512;

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    String inputType = 'document',
  }) async =>
      [];
}

class _NullQueries implements MemoryQueryAccessor {
  @override
  int insertMemoryEmbedding({
    int? messageId,
    required String chatId,
    required MemorySourceType sourceType,
    required String sourceText,
    String? senderUuid,
    String? senderName,
    MemoryVisibility visibility = MemoryVisibility.sameChat,
    List<double>? embedding,
  }) =>
      0;

  @override
  void updateMemoryEmbedding(int id, List<double> embedding) {}
}

void main() {
  late ToolRegistry registry;
  late _FakePipeline pipeline;

  setUp(() {
    registry = ToolRegistry();
    pipeline = _FakePipeline();
    registry.setContext(const ToolContext(
      senderUuid: 'user-1',
      isAdmin: false,
      chatId: 'chat-1',
      isGroup: false,
    ));
    registerMemoryTools(registry, pipeline);
  });

  group('save_memory tool', () {
    test('saves with default visibility (same_chat)', () async {
      final result = await registry.executeTool('save_memory', {
        'content': 'The team prefers morning standups at 9am.',
      });
      final data = jsonDecode(result) as Map<String, dynamic>;

      expect(data['success'], isTrue);
      expect(pipeline.calls, hasLength(1));
      expect(pipeline.calls.first.visibility, MemoryVisibility.sameChat);
      expect(pipeline.calls.first.chatId, 'chat-1');
      expect(pipeline.calls.first.senderUuid, 'user-1');
    });

    test('saves with explicit cross_chat visibility', () async {
      final result = await registry.executeTool('save_memory', {
        'content': 'My name is Nick and I am the admin.',
        'visibility': 'cross_chat',
      });
      final data = jsonDecode(result) as Map<String, dynamic>;

      expect(data['success'], isTrue);
      expect(pipeline.calls, hasLength(1));
      expect(pipeline.calls.first.visibility, MemoryVisibility.crossChat);
    });

    test('saves with explicit private visibility', () async {
      final result = await registry.executeTool('save_memory', {
        'content': 'Personal preference: dark mode.',
        'visibility': 'private',
      });
      final data = jsonDecode(result) as Map<String, dynamic>;

      expect(data['success'], isTrue);
      expect(pipeline.calls, hasLength(1));
      expect(pipeline.calls.first.visibility, MemoryVisibility.private_);
    });

    test('returns error when pipeline is null', () async {
      final noMemRegistry = ToolRegistry();
      noMemRegistry.setContext(const ToolContext(
        senderUuid: 'user-1',
        isAdmin: false,
        chatId: 'chat-1',
        isGroup: false,
      ));
      registerMemoryTools(noMemRegistry, null);

      final result = await noMemRegistry.executeTool('save_memory', {
        'content': 'Something to remember.',
      });
      final data = jsonDecode(result) as Map<String, dynamic>;

      expect(data['error'], contains('memory'));
    });

    test('content is stored correctly in queued embedding', () async {
      await registry.executeTool('save_memory', {
        'content': 'Sprint ends on Friday 2026-03-20.',
      });

      expect(pipeline.calls, hasLength(1));
      // The save_memory tool stores the content as userText with a marker
      // assistantText so it's distinguishable from conversation turns.
      expect(
        pipeline.calls.first.userText,
        contains('Sprint ends on Friday 2026-03-20.'),
      );
    });
  });
}
