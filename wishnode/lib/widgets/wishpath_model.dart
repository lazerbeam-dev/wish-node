// lib/wish_node_map.dart
import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';
import 'package:wishnode/widgets/stateless_widgets.dart';
import 'package:wishnode/widgets/task_edit_sheet.dart';
import 'dart:convert';
import '../models/wish_models.dart';
/// Colors & styling (keep vibe / easy to tweak)


/// Main node map widget.
/// - startNode on left (current)
/// - vertical phases in center (stacked left->right flow visually)
/// - goal node on right
/// - highlights current task (first incomplete) and shows simple animation on completion
class WishNodeMap extends StatefulWidget {
	final WishModel wish;
	final Future<void> Function(String wishId, String taskId) onCompleteTask;
	// optional callbacks for edit/remove - if provided the parent can handle them
	final Future<void> Function(String wishId, String taskId, String newTitle, bool newRepeat) onEditTask;
	final Future<void> Function(String wishId, String taskId)? onRemoveTask;
  final Future<void> Function(String wishId, String phaseId, String newTitle, bool newRepeat) ?onAddTask;
	final VoidCallback? onRegenerateShorterPhase; // e.g. nudge action
	final String userId;
	final Future<void> Function(String wishId, String taskId)? onUncompleteTask;

	const WishNodeMap({
		Key? key,
		required this.wish,
		required this.onCompleteTask,
		required this.onEditTask,
    this.onAddTask,
		this.onRemoveTask,
		this.onRegenerateShorterPhase,
		required this.userId,
		this.onUncompleteTask,
	}) : super(key: key);

	@override
	_WishNodeMapState createState() => _WishNodeMapState();
}

class _WishNodeMapState extends State<WishNodeMap> with TickerProviderStateMixin {
	late WishModel wish;
	String? completingTaskId;
	Map<String, AnimationController> _controllers = {};

	// Lightweight local state for repeat tasks:
	// - _repeatCounts stores how many times a repeating task was completed (local)
	// - _nextAvailableAt stores when a repeating task becomes available again
	// These are intentionally local so you can wire persistence later.
	Map<String, int> _repeatCounts = {};
	Map<String, DateTime?> _nextAvailableAt = {};

	// default repeat cooldown — change this as desired (Duration.days etc).
	// NOTE: you may want to expose this to the model or make it per-task later.
	final Duration _defaultRepeatCooldown = Duration(minutes: 1);

	@override
	void initState() {
		super.initState();
		wish = widget.wish;
		// prepare controllers for tasks (for completion pulse)
		for (var p in wish.phases) {
			for (var t in p.tasks) {
				_controllers[t.id] = AnimationController(
					vsync: this,
					duration: Duration(milliseconds: 450),
				);

				// init local repeat counters / availability if not already set
				// seed repeat counter from server-side value if present
    _repeatCounts.putIfAbsent(t.id, () {
      // TaskModel may expose `repeatedAmount` (client model) or `repeated_amount` in raw map.
      try {
        final serverCount = (t.repeatedAmount ?? 0);
        return serverCount;
      } catch (_) {
        return 0;
      }
    });
    _nextAvailableAt.putIfAbsent(t.id, () => null);
			}
		}
	}

	@override
	void didUpdateWidget(covariant WishNodeMap oldWidget) {
		super.didUpdateWidget(oldWidget);
		// If the parent replaced the wish object, update local copy and ensure controllers exist
		if (oldWidget.wish.id != widget.wish.id) {
			// dispose any controllers no longer needed
			final oldTaskIds = oldWidget.wish.phases.expand((p) => p.tasks.map((t) => t.id)).toSet();
			final newTaskIds = widget.wish.phases.expand((p) => p.tasks.map((t) => t.id)).toSet();

			for (final removedId in oldTaskIds.difference(newTaskIds)) {
				_controllers[removedId]?.dispose();
				_controllers.remove(removedId);
				_repeatCounts.remove(removedId);
				_nextAvailableAt.remove(removedId);
			}

			// create controllers for new tasks
			for (final newId in newTaskIds.difference(oldTaskIds)) {
				_controllers[newId] = AnimationController(
					vsync: this,
					duration: Duration(milliseconds: 450),
				);
				// try to seed from incoming wish object
final matching = widget.wish.phases
    .expand((p) => p.tasks)
    .firstWhere((tt) => tt.id == newId, orElse: () => TaskModel(id: "null", text: "something went wrong"));
      _repeatCounts.putIfAbsent(newId, () {
        if (matching != null) {
          return (matching.repeatedAmount ?? 0);
        }
        return 0;
      });
      _nextAvailableAt.putIfAbsent(newId, () => null);
    }

			wish = widget.wish;
			setState(() {});
		}
	}

	@override
	void dispose() {
		for (var c in _controllers.values) c.dispose();
		super.dispose();
	}

	/// Helper: is a repeating task currently due (i.e. available for completion)?
	bool _isRepeatTaskDue(TaskModel t) {
		if (t.repeat != true) return true; // non-repeat tasks are "due" if not completed
		final next = _nextAvailableAt[t.id];
		if (next == null) return true;
		return DateTime.now().isAfter(next) || DateTime.now().isAtSameMomentAs(next);
	}

	/// Finds first incomplete task (phase-order)
	/// Treats a repeating task that passed its cooldown as incomplete (so it can be the current task again).
	TaskModel? _findCurrentTask() {
		for (var p in wish.phases) {
			for (var t in p.tasks) {
				// For repeat tasks: if completed but cooldown passed, treat as incomplete (available again)
				final isDue = _isRepeatTaskDue(t);
				if (!t.completed || (t.completed && t.repeat == true && isDue)) {
					// if it's marked completed but due again, we should show it as available
					return t;
				}
			}
		}
		return null;
	}

	/// UI action to mark a task complete.
	Future<void> _handleComplete(TaskModel task) async {
		// If currently in a cooldown window and repeat task not due, block
		if (task.repeat == true && !_isRepeatTaskDue(task)) {
			final next = _nextAvailableAt[task.id];
			final s = next != null ? next.toLocal().toString() : 'later';
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Task not due until $s')));
			return;
		}

		if (task.completed || completingTaskId != null) {
			// If task shows completed but it's a repeat and due again, we still allow completion
			// so do not return here for repeat tasks that are due. Above check already handled due state.
			if (task.completed && task.repeat != true) return;
		}

		setState(() => completingTaskId = task.id);
		final controller = _controllers[task.id];
		if (controller != null) controller.forward(from: 0.0);

		try {
			print("in here: " + wish.id);
			await widget.onCompleteTask(wish.id, task.id);

			// optimistic local update
			setState(() {
				task.completed = true;
				task.completedAt = DateTime.now();
				// if repeat task, increment local counter and schedule next availability
				if (task.repeat == true) {
					_repeatCounts[task.id] = (_repeatCounts[task.id] ?? 0) + 1;
					_nextAvailableAt[task.id] = DateTime.now().add(_defaultRepeatCooldown);
				}
			});
			if (controller != null) await controller.reverse();
		} catch (e) {
			// failure animation
			if (controller != null) {
				controller.forward(from: 0.0).then((_) => controller.reverse());
			}
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to complete task')));
			print('onCompleteTask failed: $e');
		} finally {
			setState(() => completingTaskId = null);
		}
	}

	/// UI action to mark a task incomplete (un-complete). Available from dot menu.
	Future<void> _handleUncomplete(TaskModel task) async {
		// optimistic local change first
		final wasCompleted = task.completed;
		final oldCompletedAt = task.completedAt;
		setState(() {
			task.completed = false;
			task.completedAt = null;
		});

		// let parent persist if they support it
		if (widget.onUncompleteTask != null) {
			try {
				await widget.onUncompleteTask!(wish.id, task.id);
			} catch (e) {
				// rollback on failure
				setState(() {
					task.completed = wasCompleted;
					task.completedAt = oldCompletedAt;
				});
				ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to un-complete task')));
				print('onUncompleteTask failed: $e');
				return;
			}
		}
		// If parent didn't persist, we still keep local change. If this is a repeat task we don't decrement counters by default.
	}

	/// Remove a task locally and call optional external callback.
	Future<void> _removeTaskConfirmed(String taskId) async {
		// find and remove task from wish.phases
		bool removed = false;
		for (var p in wish.phases) {
			final index = p.tasks.indexWhere((t) => t.id == taskId);
			if (index != -1) {
				// dispose controller for this task
				_controllers[taskId]?.dispose();
				_controllers.remove(taskId);
				_repeatCounts.remove(taskId);
				_nextAvailableAt.remove(taskId);

				setState(() {
					p.tasks.removeAt(index);
				});
				removed = true;
				break;
			}
		}
    
		print('REMOVE TASK: wish=${wish.id} task=$taskId');

		// call parent callback if present
		if (widget.onRemoveTask != null) {
			try {
				await widget.onRemoveTask!(wish.id, taskId);
			} catch (e) {
				print('onRemoveTask callback failed: $e');
			}
		}

		if (!removed) {
			print('Attempted to remove non-existent task: $taskId');
		}
	}

	
	/// Start node now scrolls internally to avoid pushing layout.
	Widget _buildStartNode(double availableHeight) {
		final current = _findCurrentTask();
		return SizedBox(
			height: availableHeight,
			child: ClipRRect(
				borderRadius: BorderRadius.circular(12),
				child: SingleChildScrollView(
					padding: EdgeInsets.symmetric(vertical: 6),
					child: Column(
						mainAxisSize: MainAxisSize.min,
						children: [
							NodeCircle(
								label: 'You',
								subtitle: 'Start',
								color: Palette.ring,
								size: Palette.nodeSize,
								ring: true,
							),
							SizedBox(height: 8),
							Container(
								width: 160,
								padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
								decoration: BoxDecoration(
									color: Palette.card,
									borderRadius: BorderRadius.circular(8),
								),
								child: Column(
									children: [
										Text(widget.wish.title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
										if (current != null) ...[
											SizedBox(height: 6),
											Row(
												children: [
													Icon(Icons.whatshot, size: 14, color: Palette.accent),
													SizedBox(width: 6),
													Expanded(child: Text(current.text, style: TextStyle(color: Palette.muted, fontSize: 12))),
												],
											)
										]
									],
								),
							),
						],
					),
				),
			),
		);
	}

	/// Goal node also scrolls internally if content needs more room.
	Widget _buildGoalNode(double availableHeight) {
		return SizedBox(
			height: availableHeight,
			child: ClipRRect(
				borderRadius: BorderRadius.circular(12),
				child: SingleChildScrollView(
					padding: EdgeInsets.symmetric(vertical: 6),
					child: Column(
						mainAxisSize: MainAxisSize.min,
						children: [
							Container(
								width: 160,
								padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
								decoration: BoxDecoration(
									color: Palette.card,
									borderRadius: BorderRadius.circular(8),
								),
								child: Column(
									children: [
										Text('Goal', style: TextStyle(color: Palette.accent, fontWeight: FontWeight.w700)),
										SizedBox(height: 6),
										Text(widget.wish.title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
									],
								),
							),
						],
					),
				),
			),
		);
	}

	/// Phase column: vertical card with title, list of tasks
	Widget _phaseColumn(PhaseModel phase, int phaseIndex, double tasksHeight) {
		// use a single rounded radius and clip on the container itself to avoid inner seams
		final borderRadius = BorderRadius.circular(14);

		return Container(
			width: 320,
			margin: EdgeInsets.only(top: 12, left: 8, right: 8),
			padding: EdgeInsets.only(top: 12, left: 12, right: 12),
			decoration: BoxDecoration(
				color: Palette.card,
				borderRadius: borderRadius,
				boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
			),
			clipBehavior: Clip.none, // <-- ensure child content is clipped to same radius
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Row(
						children: [
							PhaseDot(index: phaseIndex),
							SizedBox(width: 10),
							Expanded(child: Text(phase.title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
							SizedBox(width: 8),
							Text('${phase.tasks.where((t) => t.completed).length}/${phase.tasks.length}', style: TextStyle(color: Palette.muted)),
						],
					),
					SizedBox(height: 10),
					SizedBox(
  height: tasksHeight + 52,
  child: Column(
    children: [
      // the scrollable task list
      Expanded(
        child: ListView.builder(
          padding: EdgeInsets.only(top: 6), // small bottom pad for scroll space
          physics: AlwaysScrollableScrollPhysics(),
          itemCount: phase.tasks.length,
          itemBuilder: (context, idx) {
            final t = phase.tasks[idx];
            return Padding(
              padding: const EdgeInsets.only(left: 2, right: 2),
              child: KeyedSubtree(key: ValueKey(t.id), child: _taskTile(t)),
            );
          },
        ),
      ),

      // small gap then centered green plus
      SizedBox(height: 10),
      Center(
        child: AddTaskButton(onPressed: () async {
          // open the small sheet to collect title / repeat
          final res = await showTaskAddSheet(context);
          if (res == null) return;
          final title = (res['title'] ?? '').toString();
          final repeat = res['repeat'] == true;

          // create optimistic TaskModel (assumes TaskModel constructor matches yours)
          final newTask = TaskModel(
            id: UniqueKey().toString(),
            text: title,
            repeat: repeat,
            completed: false,
          );

          // add controller for animation
          _controllers[newTask.id] = AnimationController(vsync: this, duration: Duration(milliseconds: 450));

          // optimistic local insert
          setState(() {
            phase.tasks.add(newTask);
            _repeatCounts.putIfAbsent(newTask.id, () => 0);
            _nextAvailableAt.putIfAbsent(newTask.id, () => null);
          });

          // call parent persistence callback if provided; rollback on failure
          if (widget.onAddTask != null) {
            try {
              await widget.onAddTask!(wish.id, phase.id, title, repeat);
            } catch (e) {
              // rollback
              setState(() {
                phase.tasks.removeWhere((tt) => tt.id == newTask.id);
                _controllers[newTask.id]?.dispose();
                _controllers.remove(newTask.id);
                _repeatCounts.remove(newTask.id);
                _nextAvailableAt.remove(newTask.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add task')));
              print('onAddTask failed: $e');
            }
          }
        }),
      ),
    ],
  ),
),
				],
			),
		);
	}

	Widget _taskTile(TaskModel t) {
		final isCurrent = _findCurrentTask()?.id == t.id;
		final controller = _controllers[t.id];
		final scaleAnim = controller != null ? Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut)) : null;

		// compute whether this task should be shown as 'done' or 'available' for repeat tasks
		final isRepeat = t.repeat == true;
		final repeatDue = isRepeat ? _isRepeatTaskDue(t) : true;
		final displayDone = t.completed && !(isRepeat && repeatDue);

		return ScaleTransition(
			scale: scaleAnim ?? AlwaysStoppedAnimation(1.0),
			child: AnimatedContainer(
				duration: Duration(milliseconds: 220),
				padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
				decoration: BoxDecoration(
					color: displayDone ? Color(0xFF10141E) : Palette.bg.withOpacity(0.02),
					borderRadius: BorderRadius.circular(10),
					border: Border.all(color: isCurrent ? Palette.ring.withOpacity(0.9) : Colors.transparent, width: 1.5),
				),
				child: Row(
					children: [
						GestureDetector(
							onTap: (!displayDone && repeatDue) ? () => _handleComplete(t) : null,
							child: AnimatedContainer(
								duration: Duration(milliseconds: 220),
								width: 36,
								height: 36,
								decoration: BoxDecoration(
									shape: BoxShape.circle,
									gradient: displayDone ? LinearGradient(colors: [Palette.good.withOpacity(0.9), Palette.good.withOpacity(0.6)]) : null,
									border: Border.all(color: displayDone ? Palette.good : Palette.muted.withOpacity(0.35)),
								),
								child: Center(
									// **CHANGE**: always use an unfilled circle for uncompleted tasks (no play_arrow)
									child: displayDone ? Icon(Icons.check, size: 18, color: Colors.black) : Icon(Icons.radio_button_unchecked, size: 18, color: Palette.muted),
								),
							),
						),
						SizedBox(width: 12),
						Expanded(
							child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
								Text(t.text, style: TextStyle(color: Colors.white, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500)),
								SizedBox(height: 4),
								Row(
									children: [
										if (t.repeat == true) ...[
											Icon(Icons.repeat, size: 14, color: Palette.accent),
											SizedBox(width: 6),
											Text('repeat', style: TextStyle(color: Palette.muted, fontSize: 12)),
                      SizedBox(width: 6),
                      // show local repeat counter if available
                      Text('×${_repeatCounts[t.id] ?? 0}', style: TextStyle(color: Palette.muted, fontSize: 12, fontWeight: FontWeight.w700)),
										],
										if (displayDone) ...[
											SizedBox(width: 8),
											Text('done', style: TextStyle(color: Palette.good, fontSize: 12, fontWeight: FontWeight.w700))
										]
									],
								)
							]),
						),
						SizedBox(width: 8),
						// Show the dot menu for both completed and non-completed tasks so we can add "Un-complete"
						IconButton(
							icon: Icon(Icons.more_horiz, color: Palette.muted),
							onPressed: () {
								showModalBottomSheet(context: context, backgroundColor: Palette.card, builder: (_) {
									return Padding(
										padding: const EdgeInsets.all(12.0),
										child: Column(mainAxisSize: MainAxisSize.min, children: [
											ListTile(
												leading: Icon(Icons.edit, color: Colors.white),
												title: Text('Edit task', style: TextStyle(color: Colors.white)),
												onTap: () async {
                            Navigator.of(context).pop();
                            final res = await showTaskEditSheet(context, initialTitle: t.text, initialRepeat: t.repeat);
                            if (res == null) return;

                            final newTitle = (res['title'] ?? '').toString();
                            final newRepeat = res['repeat'] == true;

                            // save old for rollback
                            final oldText = t.text;
                            final oldRepeat = t.repeat;

                            // optimistic change (mutable model)
                            setState(() {
                              t.text = newTitle;
                              t.repeat = newRepeat;
                              _repeatCounts.putIfAbsent(t.id, () => 0);
                              _nextAvailableAt.putIfAbsent(t.id, () => null);
                            });

                            try {
                              await widget.onEditTask(wish.id, t.id, newTitle, newRepeat);
                              // success - UI already reflects change
                            } catch (e) {
                              // rollback on failure
                              setState(() {
                                t.text = oldText;
                                t.repeat = oldRepeat;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save task edit')));
                              print('onEditTask failed: $e');
                            }
                          },

												),
                        // If task is completed, show "Mark as incomplete" option
                        if (t.completed) ...[
                          ListTile(
                            leading: Icon(Icons.undo, color: Colors.white),
                            title: Text('Mark as incomplete', style: TextStyle(color: Colors.white)),
                            onTap: () {
                              Navigator.of(context).pop();
                              _handleUncomplete(t);
                            },
                          ),
                        ],
												// inside the bottom sheet builder where you create the ListTile for Remove
                        ListTile(
                          leading: Icon(Icons.delete, color: Palette.danger),
                          title: Text('Remove', style: TextStyle(color: Palette.danger)),
                          onTap: () {
                            // close the bottom sheet first
                            Navigator.of(context).pop();
                            // then remove immediately (no confirmation)
                            _removeTaskConfirmed(t.id);
                          },
                        ),
											]),
										);
									});
								},
							)
					],
				),
			),
		);
	}

	@override
	Widget build(BuildContext context) {
		final phases = wish.phases;
		return Container(
			color: Palette.bg,
			padding: EdgeInsets.only(top: 18, left: 18, right: 18),
			child: LayoutBuilder(builder: (context, constraints) {
				// compute a robust tasksHeight for each phase column
				final totalHeight = constraints.maxHeight;
				final headerReserve = 140.0; // space taken by start/goal + top padding; tweak if needed
				final safetyBuffer = 0; // reduce tiny overflow risk
				final tasksHeight = (totalHeight - headerReserve - safetyBuffer).clamp(100.0, totalHeight);

				return SingleChildScrollView(
					scrollDirection: Axis.horizontal,
					child: Row(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							// left column: start node + optional small panel (bounded)
							SizedBox(
								width: 220,
								child: Column(
									children: [
										_buildStartNode(tasksHeight),
										SizedBox(height: 18),
									],
								),
							),

							SizedBox(width: 28),

							// phases laid out left-to-right as tall columns
							for (int i = 0; i < phases.length; i++) _phaseColumn(phases[i], i + 1, tasksHeight),

							SizedBox(width: 28),

							// goal (bounded)
							SizedBox(width: 220, child: _buildGoalNode(tasksHeight)),
						],
					),
				);
			}),
		);
	}
}
