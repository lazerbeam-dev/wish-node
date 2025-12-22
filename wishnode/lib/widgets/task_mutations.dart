import 'package:flutter/material.dart';
import 'package:wishnode/utils/log.dart';
import 'package:wishnode/widgets/task_edit_sheet.dart';
import '../models/wish_models.dart';

typedef LocalCreateCallback = void Function(TaskModel t);
typedef LocalRollbackCallback = void Function(TaskModel t);

class TaskMutations {
	/// Adds a task optimistically. Caller passes callbacks to perform local insertion and rollback.
	/// - context: required for showTaskAddSheet
	/// - phase: target phase to mutate locally
	/// - onCreateLocal: called once with the created TaskModel inside a setState (caller responsibility)
	/// - onRollbackLocal: called if persistence fails
	/// - onPersist: optional persistence callback from parent (wishNodeMap.widget.onAddTask). If null, no network call attempted.
	/// Returns the created TaskModel (or null if cancelled).
	static Future<TaskModel?> addTaskToPhase({
	required BuildContext context,
	required PhaseModel phase,
	required String wishId,
	required LocalCreateCallback onCreateLocal,
	required Future<String> Function(
		String wishId,
		String phaseId,
		String newTitle,
		bool newRepeat,
	) onPersist,
}) async {
	final res = await showTaskAddSheet(context);
	if (res == null) return null;

	final title = (res['title'] ?? '').toString();
	final repeat = res['repeat'] == true;

	try {
		// 1️⃣ persist first
		final serverTaskId = await onPersist(
			wishId,
			phase.id,
			title,
			repeat,
		);

		// 2️⃣ create task with real ID
		final newTask = TaskModel(
			id: serverTaskId,
			phaseId: phase.id,
			text: title,
			repeat: repeat,
			completed: false,
		);

		// 3️⃣ insert locally (inside caller setState)
		onCreateLocal(newTask);

		return newTask;
	} catch (e) {
		ScaffoldMessenger.of(context).showSnackBar(
			SnackBar(content: Text('Failed to add task')),
		);
		Log.d('onAddTask failed: $e');
		return null;
	}
}

	/// Remove task: caller performs the local removal in onLocalRemove, and optionally provide onPersistRemove
	static Future<void> removeTaskConfirmed({
		required WishModel wish,
		required String taskId,
		required VoidCallback onLocalRemove,
		required VoidCallback onRecalcPhase,
		Future<void> Function(String wishId, String taskId)? onPersistRemove,
	}) async {
		// local remove
		onLocalRemove();
		onRecalcPhase();

		// try persistence if provided, but don't block UI if it fails
		if (onPersistRemove != null) {
			try {
				await onPersistRemove(wish.id, taskId);
			} catch (e) {
				// best-effort: log and continue
				Log.d('onRemoveTask callback failed: $e');
			}
		}
	}
}
