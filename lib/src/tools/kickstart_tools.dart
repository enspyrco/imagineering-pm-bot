/// Custom tools for kickstart onboarding flow.
///
/// - `advance_kickstart`: Move to the next kickstart step (agent-initiated).
/// - `complete_kickstart`: Mark kickstart as done (agent-initiated at step 5).
library;

import 'dart:convert';

import '../agent/tool_registry.dart';
import '../kickstart/kickstart_state.dart';

/// Callback type for sending a message to a group.
typedef SendGroupMessage = Future<void> Function(
    String groupId, String message);

/// Registers kickstart tools with the [ToolRegistry].
///
/// The [sendGroupMessage] callback is used by `post_kickstart_summary` to
/// send the onboarding summary back to the group chat.
void registerKickstartTools(
  ToolRegistry registry,
  KickstartState state, {
  required SendGroupMessage sendGroupMessage,
}) {
  registry.registerCustomTool(_advanceKickstartTool(state));
  registry.registerCustomTool(_completeKickstartTool(state));
  registry.registerCustomTool(_postKickstartSummaryTool(sendGroupMessage));
}

CustomToolDef _advanceKickstartTool(KickstartState state) {
  return CustomToolDef(
    name: 'advance_kickstart',
    description: 'Advance the kickstart onboarding to the next step. '
        'Call this when the current step is complete (user confirmed, '
        'or said "done", "next", or "skip").',
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
      final nextStep = state.advanceKickstart(groupId);

      if (nextStep == null) {
        return jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'No active kickstart to advance, or already on the '
              'final step. Use complete_kickstart to finish.',
        });
      }

      return jsonEncode(<String, dynamic>{
        'success': true,
        'new_step': nextStep.number,
        'new_step_label': nextStep.label,
      });
    },
  );
}

CustomToolDef _completeKickstartTool(KickstartState state) {
  return CustomToolDef(
    name: 'complete_kickstart',
    description: 'Mark the kickstart onboarding as complete. '
        'Call this at the end of Step 5 (Dream Primer) after '
        'summarizing the setup and introducing the dream cycle.',
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
      state.completeKickstart(groupId);

      return jsonEncode(<String, dynamic>{
        'success': true,
        'message': 'Kickstart complete! Now compose a summary of what was '
            'set up and call post_kickstart_summary to announce it to the group.',
      });
    },
  );
}

CustomToolDef _postKickstartSummaryTool(SendGroupMessage sendGroupMessage) {
  return CustomToolDef(
    name: 'post_kickstart_summary',
    description: 'Post a kickstart onboarding summary to the group chat. '
        'Call this after complete_kickstart to announce what was set up.',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'group_id': <String, dynamic>{
          'type': 'string',
          'description': 'The group ID to post the summary to.',
        },
        'summary': <String, dynamic>{
          'type': 'string',
          'description': 'The onboarding summary message to post.',
        },
      },
      'required': <String>['group_id', 'summary'],
    },
    handler: (args) async {
      final groupId = args['group_id'] as String;
      final summary = args['summary'] as String;

      try {
        await sendGroupMessage(groupId, summary);
        return jsonEncode(<String, dynamic>{
          'success': true,
          'message': 'Summary posted to group.',
        });
      } on Exception catch (e) {
        return jsonEncode(<String, dynamic>{
          'success': false,
          'error': 'Failed to post summary: $e',
        });
      }
    },
  );
}
