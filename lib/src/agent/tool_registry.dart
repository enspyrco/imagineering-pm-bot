import 'dart:convert';

import '../mcp/mcp_manager.dart';

/// Per-request context set before processing each message.
///
/// Allows tool handlers to check admin status without changing their signature.
class ToolContext {
  const ToolContext({
    required this.senderUuid,
    required this.isAdmin,
    required this.chatId,
    this.isGroup = false,
  });

  final String? senderUuid;
  final bool isAdmin;
  final String chatId;
  final bool isGroup;
}

/// A custom (non-MCP) tool definition with its handler function.
class CustomToolDef {
  const CustomToolDef({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.requiresAdmin = false,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<String> Function(Map<String, dynamic> args) handler;

  /// When `true`, the registry rejects execution if the current context
  /// is not an admin. This enforces "admin-only" at the tool level rather
  /// than relying on the LLM to respect the tool description.
  final bool requiresAdmin;
}

/// Unified tool description for the Claude API.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

/// Merges MCP-discovered tools and custom tools into a single registry.
class ToolRegistry {
  final Map<String, CustomToolDef> _customTools = {};
  McpManager? _mcpManager;

  /// Current per-request context. Set via [setContext] before each message.
  ToolContext? _context;

  /// Public read access to the current per-request context.
  ///
  /// Used by tools that need sender/chat metadata (e.g., `save_memory`).
  ToolContext? get context => _context;

  void registerCustomTool(CustomToolDef tool) {
    _customTools[tool.name] = tool;
  }

  void setMcpManager(McpManager manager) {
    _mcpManager = manager;
  }

  /// Sets the per-request context (sender, admin status) before processing
  /// a message. Tool handlers with [CustomToolDef.requiresAdmin] will be
  /// rejected if [ToolContext.isAdmin] is `false`.
  void setContext(ToolContext context) {
    _context = context;
  }

  List<ToolDefinition> getAllToolDefinitions() {
    final tools = <ToolDefinition>[];
    if (_mcpManager != null) {
      for (final mcpTool in _mcpManager!.getAllTools()) {
        tools.add(ToolDefinition(
          name: mcpTool.name,
          description: mcpTool.description,
          inputSchema: mcpTool.inputSchema,
        ));
      }
    }
    for (final custom in _customTools.values) {
      tools.add(ToolDefinition(
        name: custom.name,
        description: custom.description,
        inputSchema: custom.inputSchema,
      ));
    }
    return tools;
  }

  Future<String> executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final custom = _customTools[toolName];
    if (custom != null) {
      if (custom.requiresAdmin && !(_context?.isAdmin ?? false)) {
        return jsonEncode(<String, dynamic>{
          'error': 'This action requires admin privileges.',
          'tool': toolName,
        });
      }
      return custom.handler(args);
    }
    if (_mcpManager != null) return _mcpManager!.callTool(toolName, args);
    throw Exception('Tool not found: $toolName');
  }
}
