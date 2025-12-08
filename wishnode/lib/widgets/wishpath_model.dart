// lib/wish_node_map.dart
import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';
import 'package:wishnode/widgets/stateless_widgets.dart';
import 'package:wishnode/widgets/task_edit_sheet.dart';
import 'dart:convert';
import '../models/wish_models.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';
import 'task_tile.dart';
import 'phase_column.dart';
import 'celebration.dart';

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
	final Future<void> Function(String wishId, String phaseId, String newTitle, bool newRepeat)? onAddTask;
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
	late CelebrationService _celebration;
	String? completingTaskId;
	Map<String, AnimationController> _controllers = {};

	// Phase animation controllers (for "all tasks completed" celebration)
	Map<String, AnimationController> _phaseControllers = {};
	Map<String, bool> _phaseWasCompleted = {};

	// Lightweight local state for repeat tasks:
	// - _repeatCounts stores how many times a repeating task was completed (local)
	// - _nextAvailableAt stores when a repeating task becomes available again
	// These are intentionally local so you can wire persistence later.
	Map<String, int> _repeatCounts = {};
	Map<String, DateTime?> _nextAvailableAt = {};

	// default repeat cooldown — change this as desired (Duration.days etc).
	// NOTE: you may want to expose this to the model or make it per-task later.
	final Duration _defaultRepeatCooldown = Duration(minutes: 1);

	// Confetti controller for whole-wish confetti burst
	late ConfettiController _confettiController;

	// time between chained phase celebrations
	final Duration _phaseStagger = Duration(milliseconds: 120);

	// whether we've already run the full-wish celebration (avoid duplicates)
	bool _wishCelebrated = false;

	@override
	void initState() {
		super.initState();
		wish = widget.wish;

		// prepare controllers for tasks (for completion pulse)
		for (var p in wish.phases) {
			// create/seed phase controller
			_phaseControllers[p.id] = AnimationController(vsync: this, duration: Duration(milliseconds: 700));
			_phaseWasCompleted.putIfAbsent(p.id, () => _isPhaseCompleted(p));

			for (var t in p.tasks) {
				_controllers[t.id] = AnimationController(
					vsync: this,
					duration: Duration(milliseconds: 450),
				);

				// init local repeat counters / availability if not already set
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

		// confetti init
		_confettiController = ConfettiController(duration: Duration(seconds: 5));

		// create celebration service (phaseControllers already populated in init loop)
		_celebration = CelebrationService(
			phaseControllers: _phaseControllers,
			confettiController: _confettiController,
			perPhaseHold: Duration(milliseconds: 200),
			phaseStagger: _phaseStagger,
		);
		_wishCelebrated = false;
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
					try {
						return (matching.repeatedAmount ?? 0);
					} catch (_) {
						return 0;
					}
				});
				_nextAvailableAt.putIfAbsent(newId, () => null);
			}

			// ensure phase controllers map matches new phases (create new, dispose removed)
			final oldPhaseIds = oldWidget.wish.phases.map((p) => p.id).toSet();
			final newPhaseIds = widget.wish.phases.map((p) => p.id).toSet();

			for (final removed in oldPhaseIds.difference(newPhaseIds)) {
				_phaseControllers[removed]?.dispose();
				_phaseControllers.remove(removed);
				_phaseWasCompleted.remove(removed);
			}

			for (final added in newPhaseIds.difference(oldPhaseIds)) {
				_phaseControllers[added] = AnimationController(vsync: this, duration: Duration(milliseconds: 700));
				// seed wasCompleted state from incoming wish
				final matching = widget.wish.phases.firstWhere((pp) => pp.id == added, orElse: () => PhaseModel(id: 'null', title: '', tasks: []));
				_phaseWasCompleted.putIfAbsent(added, () => _isPhaseCompleted(matching));
			}

			wish = widget.wish;
			setState(() {});
		}
	}

	@override
	void dispose() {
		for (var c in _controllers.values) c.dispose();
		for (var c in _phaseControllers.values) c.dispose();
		_confettiController.dispose();
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

	/// Is the phase fully completed?
	bool _isPhaseCompleted(PhaseModel p) {
		if (p.tasks.isEmpty) return false;
		return p.tasks.every((t) => t.completed == true);
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

			// After marking complete, check its phase: if whole phase now complete and wasn't before -> celebrate
			final phase = wish.phases.firstWhere((p) => p.tasks.any((tt) => tt.id == task.id), orElse: () => PhaseModel(id: 'null', title: '', tasks: []));
			if (phase.id != 'null') {
				final completedNow = _isPhaseCompleted(phase);
				final wasCompleted = _phaseWasCompleted[phase.id] ?? false;
				if (completedNow && !wasCompleted) {
					// determine if this is the last phase and all phases are complete now
					final isLastPhase = wish.phases.isNotEmpty && wish.phases.last.id == phase.id;
					final allPhasesComplete = wish.phases.every((pp) => pp.tasks.isNotEmpty && pp.tasks.every((tt) => tt.completed == true));

					if (isLastPhase && allPhasesComplete) {
						// chain celebrations across all phases and confetti
						await _celebration.celebrateAllPhasesSequential(
							wish.phases.map((p) => p.id).toList(),
							finalPhaseFirst: true,
						);
						for (final p in wish.phases) {
							_phaseWasCompleted[p.id] = true;
						}
					} else {
						// only celebrate this single phase as before
						await _celebration.celebratePhase(phase.id);
						_phaseWasCompleted[phase.id] = true;
					}
				}
			}
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

	/// Helper: create & add a new task optimistically, call parent persistence and rollback on failure.
	Future<void> _addTaskToPhase(int phaseIndex, PhaseModel phase, BuildContext context) async {
		final res = await showTaskAddSheet(context);
		if (res == null) return;
		final title = (res['title'] ?? '').toString();
		final repeat = res['repeat'] == true;

		final newTask = TaskModel(id: UniqueKey().toString(), text: title, repeat: repeat, completed: false);

		_controllers[newTask.id] = AnimationController(vsync: this, duration: Duration(milliseconds: 450));

		setState(() {
			phase.tasks.add(newTask);
			_repeatCounts.putIfAbsent(newTask.id, () => 0);
			_nextAvailableAt.putIfAbsent(newTask.id, () => null);
			_phaseWasCompleted[phase.id] = _isPhaseCompleted(phase);
			_wishCelebrated = false;
		});

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

		// mark phase as not completed (so future completion triggers celebration)
		final phase = wish.phases.firstWhere((p) => p.tasks.any((tt) => tt.id == task.id), orElse: () => PhaseModel(id: 'null', title: '', tasks: []));
		if (phase.id != 'null') {
			_phaseWasCompleted[phase.id] = false;
		}

		// allow re-running full-wish celebration if tasks change after an uncomplete
		_wishCelebrated = false;

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

				// if removing the last task from a phase, ensure phase completed state is recalculated
				_phaseWasCompleted[p.id] = _isPhaseCompleted(p);

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

	/// Custom star path for confetti particles (optional)
	Path _drawStarPath(Size size) {
		final Path path = Path();
		const int points = 5;
		final double outerRadius = size.width / 2;
		final double innerRadius = outerRadius / 2.5;
		final double step = pi / points;
		double rotation = -pi / 2;
		for (int i = 0; i < points * 2; i++) {
			final double radius = i.isEven ? outerRadius : innerRadius;
			final double x = radius * cos(rotation) + outerRadius;
			final double y = radius * sin(rotation) + outerRadius;
			if (i == 0) path.moveTo(x, y);
			else path.lineTo(x, y);
			rotation += step;
		}
		path.close();
		return path;
	}

	@override
	Widget build(BuildContext context) {
		final phases = wish.phases;
		return Stack(
			children: [
				Container(
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
									for (int i = 0; i < phases.length; i++)
										PhaseColumn(
											phase: phases[i],
											phaseIndex: i + 1,
											tasksHeight: tasksHeight,
											// pass celebration animations derived from _phaseControllers
											celebrationScale: _phaseControllers[phases[i].id] != null
												? Tween(begin: 0.6, end: 1.12).animate(CurvedAnimation(parent: _phaseControllers[phases[i].id]!, curve: Curves.elasticOut))
												: null,
											celebrationFade: _phaseControllers[phases[i].id] != null
												? Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _phaseControllers[phases[i].id]!, curve: Curves.easeOut))
												: null,
											// taskBuilder creates the TaskTile exactly as you had it before
											taskBuilder: (context, t) => TaskTile(
												task: t,
												isCurrent: _findCurrentTask()?.id == t.id,
												displayDone: t.completed && !(t.repeat == true && _isRepeatTaskDue(t)),
												onComplete: (!t.completed || (t.repeat == true && _isRepeatTaskDue(t))) ? () => _handleComplete(t) : null,
												onEdit: () async {
													// reuse your existing edit flow: open sheet and call widget.onEditTask etc.
													// don't force a navigator pop here unless appropriate in your flow
												},
												onRemove: () => _removeTaskConfirmed(t.id),
												scaleAnim: _controllers[t.id] != null ? Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _controllers[t.id]!, curve: Curves.easeOut)) : null,
											),
											onAddPressed: () => _addTaskToPhase(i, phases[i], context),
										),

									SizedBox(width: 28),

									// goal (bounded)
									SizedBox(width: 220, child: _buildGoalNode(tasksHeight)),
								],
							),
						);
					}),
				),

				// Confetti overlay - full screen, non-interactive
				Positioned(
					child: ConfettiOverlay(
						controller: _confettiController,
						createParticlePath: _drawStarPath,
					),
				),
			],
		);
	}
}
