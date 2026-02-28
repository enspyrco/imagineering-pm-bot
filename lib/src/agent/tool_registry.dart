import '../mcp/mcp_manager.dart';

/// A custom (non-MCP) tool definition with its handler function.
class CustomToolDef {
  const CustomToolDef({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<String> Function(Map<String, dynamic> args) handler;
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

  void registerCustomTool(CustomToolDef tool) {
    _customTools[tool.name] = tool;
  }

  void setMcpManager(McpManager manager) {
    _mcpManager = manager;
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
    if (custom != null) return custom.handler(args);
    if (_mcpManager != null) return _mcpManager!.callTool(toolName, args);
    throw Exception('Tool not found: $toolName');
  }
}
