/// Custom tools for chat configuration and user mapping.
///
/// Chat config tools (admin-gated via `requiresAdmin`):
/// - `get_chat_config`: Fetch workspace link and default board for a group.
/// - `link_workspace`: Link a group to a Kan workspace. (admin)
/// - `unlink_workspace`: Remove the workspace link. (admin)
/// - `set_default_board`: Set the default board/list for card creation. (admin)
///
/// User mapping tools:
/// - `get_user_mapping`: Look up a user's Kan account by their ID.
/// - `create_user_mapping`: Map a user to a Kan email. (admin)
/// - `remove_user_mapping`: Remove a user mapping. (admin)
/// - `list_user_mappings`: List all user → Kan user mappings.
library;

import 'dart:convert';

import '../agent/tool_registry.dart';
import '../db/queries.dart';

/// Registers all chat config and user mapping tools with the [ToolRegistry].
void registerChatConfigTools(ToolRegistry registry, Queries queries) {
  registry.registerCustomTool(_getChatConfigTool(queries));
  registry.registerCustomTool(_linkWorkspaceTool(queries));
  registry.registerCustomTool(_unlinkWorkspaceTool(queries));
  registry.registerCustomTool(_setDefaultBoardTool(queries));
  registry.registerCustomTool(_getUserMappingTool(queries));
  registry.registerCustomTool(_createUserMappingTool(queries));
  registry.registerCustomTool(_removeUserMappingTool(queries));
  registry.registerCustomTool(_listUserMappingsTool(queries));
}

// ---------------------------------------------------------------------------
// Chat Config tools
// ---------------------------------------------------------------------------

CustomToolDef _getChatConfigTool(Queries queries) {
  return CustomToolDef(
    name: 'get_chat_config',
    description: 'Get the workspace link and default board configuration for a '
        'group. Returns null fields if not configured.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'group_id': <String, dynamic>{
          'type': 'string',
          'description': 'The group ID to look up.',
        },
      },
      'required': <String>['group_id'],
    },
    handler: (args) async {
      final groupId = args['group_id'] as String;
      final workspace = queries.getWorkspaceLink(groupId);
      final board = queries.getDefaultBoardConfig(groupId);

      return jsonEncode(<String, dynamic>{
        'workspace': workspace != null
            ? <String, dynamic>{
                'workspace_public_id': workspace.workspacePublicId,
                'workspace_name': workspace.workspaceName,
                'created_at': workspace.createdAt,
              }
            : null,
        'default_board': board != null
            ? <String, dynamic>{
                'board_public_id': board.boardPublicId,
                'board_name': board.boardName,
                'list_public_id': board.listPublicId,
                'list_name': board.listName,
              }
            : null,
      });
    },
  );
}

CustomToolDef _linkWorkspaceTool(Queries queries) {
  return CustomToolDef(
    requiresAdmin: true,
    name: 'link_workspace',
    description: 'Link a group to a Kan workspace. Admin-only. '
        'Only one workspace per group is allowed.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'group_id': <String, dynamic>{
          'type': 'string',
          'description': 'The group ID.',
        },
        'workspace_public_id': <String, dynamic>{
          'type': 'string',
          'description': 'The Kan workspace public ID.',
        },
        'workspace_name': <String, dynamic>{
          'type': 'string',
          'description': 'Human-readable workspace name.',
        },
        'created_by_uuid': <String, dynamic>{
          'type': 'string',
          'description': 'The user ID of the admin creating the link.',
        },
      },
      'required': <String>[
        'group_id',
        'workspace_public_id',
        'workspace_name',
        'created_by_uuid',
      ],
    },
    handler: (args) async {
      final groupId = args['group_id'] as String;

      // Check if already linked.
      final existing = queries.getWorkspaceLink(groupId);
      if (existing != null) {
        return jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'This group is already linked to workspace '
              '"${existing.workspaceName}". Unlink it first.',
        });
      }

      queries.createWorkspaceLink(
        groupId: groupId,
        workspacePublicId: args['workspace_public_id'] as String,
        workspaceName: args['workspace_name'] as String,
        createdByUuid: args['created_by_uuid'] as String,
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'workspace_name': args['workspace_name'],
      });
    },
  );
}

CustomToolDef _unlinkWorkspaceTool(Queries queries) {
  return CustomToolDef(
    requiresAdmin: true,
    name: 'unlink_workspace',
    description: 'Remove the workspace link for a group. Admin-only.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'group_id': <String, dynamic>{
          'type': 'string',
          'description': 'The group ID.',
        },
      },
      'required': <String>['group_id'],
    },
    handler: (args) async {
      final groupId = args['group_id'] as String;
      final existing = queries.getWorkspaceLink(groupId);
      if (existing == null) {
        return jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'This group is not linked to any workspace.',
        });
      }

      queries.deleteWorkspaceLink(groupId);
      return jsonEncode(<String, dynamic>{
        'success': true,
        'unlinked_workspace': existing.workspaceName,
      });
    },
  );
}

CustomToolDef _setDefaultBoardTool(Queries queries) {
  return CustomToolDef(
    requiresAdmin: true,
    name: 'set_default_board',
    description: 'Set the default board and list for card creation in a '
        'group. Admin-only. New cards created via natural language will '
        'be placed in this board/list by default.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'group_id': <String, dynamic>{
          'type': 'string',
          'description': 'The group ID.',
        },
        'board_public_id': <String, dynamic>{
          'type': 'string',
          'description': 'The Kan board public ID.',
        },
        'board_name': <String, dynamic>{
          'type': 'string',
          'description': 'Human-readable board name.',
        },
        'list_public_id': <String, dynamic>{
          'type': 'string',
          'description': 'The Kan list public ID.',
        },
        'list_name': <String, dynamic>{
          'type': 'string',
          'description': 'Human-readable list name.',
        },
      },
      'required': <String>[
        'group_id',
        'board_public_id',
        'board_name',
        'list_public_id',
        'list_name',
      ],
    },
    handler: (args) async {
      queries.upsertDefaultBoardConfig(
        groupId: args['group_id'] as String,
        boardPublicId: args['board_public_id'] as String,
        boardName: args['board_name'] as String,
        listPublicId: args['list_public_id'] as String,
        listName: args['list_name'] as String,
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'board_name': args['board_name'],
        'list_name': args['list_name'],
      });
    },
  );
}

// ---------------------------------------------------------------------------
// User Mapping tools
// ---------------------------------------------------------------------------

CustomToolDef _getUserMappingTool(Queries queries) {
  return CustomToolDef(
    name: 'get_user_mapping',
    description: 'Look up a user\'s Kan account mapping by their user ID.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'user_id': <String, dynamic>{
          'type': 'string',
          'description': 'The user ID to look up.',
        },
      },
      'required': <String>['user_id'],
    },
    handler: (args) async {
      final link = queries.getUserLink(args['user_id'] as String);
      if (link == null) {
        return jsonEncode(<String, dynamic>{
          'found': false,
        });
      }

      return jsonEncode(<String, dynamic>{
        'found': true,
        'user_id': link.userId,
        'display_name': link.displayName,
        'kan_user_email': link.kanUserEmail,
        'workspace_member_public_id': link.workspaceMemberPublicId,
      });
    },
  );
}

CustomToolDef _createUserMappingTool(Queries queries) {
  return CustomToolDef(
    requiresAdmin: true,
    name: 'create_user_mapping',
    description: 'Map a user (by ID) to their Kan account email. '
        'Admin-only.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'user_id': <String, dynamic>{
          'type': 'string',
          'description': 'The user ID.',
        },
        'kan_user_email': <String, dynamic>{
          'type': 'string',
          'description': 'The user\'s Kan account email.',
        },
        'display_name': <String, dynamic>{
          'type': 'string',
          'description': 'The user\'s display name.',
        },
        'created_by_uuid': <String, dynamic>{
          'type': 'string',
          'description': 'The user ID of the admin creating this mapping.',
        },
      },
      'required': <String>['user_id', 'kan_user_email'],
    },
    handler: (args) async {
      final uuid = args['user_id'] as String;

      // Check if already mapped.
      final existing = queries.getUserLink(uuid);
      if (existing != null) {
        return jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'User $uuid is already mapped to '
              '${existing.kanUserEmail}. Remove the mapping first.',
        });
      }

      queries.createUserLink(
        userId: uuid,
        kanUserEmail: args['kan_user_email'] as String,
        displayName: args['display_name'] as String?,
        createdByUuid: args['created_by_uuid'] as String?,
      );

      return jsonEncode(<String, dynamic>{
        'success': true,
        'user_id': uuid,
        'kan_user_email': args['kan_user_email'],
      });
    },
  );
}

CustomToolDef _removeUserMappingTool(Queries queries) {
  return CustomToolDef(
    requiresAdmin: true,
    name: 'remove_user_mapping',
    description: 'Remove a user\'s Kan account mapping. Admin-only.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'user_id': <String, dynamic>{
          'type': 'string',
          'description': 'The user ID of the user to unmap.',
        },
      },
      'required': <String>['user_id'],
    },
    handler: (args) async {
      final uuid = args['user_id'] as String;
      final existing = queries.getUserLink(uuid);
      if (existing == null) {
        return jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'No mapping found for user $uuid.',
        });
      }

      queries.deleteUserLink(uuid);
      return jsonEncode(<String, dynamic>{
        'success': true,
        'removed_email': existing.kanUserEmail,
      });
    },
  );
}

CustomToolDef _listUserMappingsTool(Queries queries) {
  return CustomToolDef(
    name: 'list_user_mappings',
    description: 'List all user → Kan user mappings.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
    handler: (args) async {
      final links = queries.getAllUserLinks();
      return jsonEncode(<String, dynamic>{
        'count': links.length,
        'mappings': <Map<String, dynamic>>[
          for (final link in links)
            <String, dynamic>{
              'user_id': link.userId,
              'display_name': link.displayName,
              'kan_user_email': link.kanUserEmail,
            },
        ],
      });
    },
  );
}
