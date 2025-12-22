import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';
import 'package:wishnode/widgets/task_edit_sheet.dart';
import '../models/wish_models.dart';
import 'package:confetti/confetti.dart';
import 'task_tile.dart';
import 'phase_column.dart';
import 'celebration.dart';
import 'dart:async';


// Extracted helpers
import 'repeat_task_service.dart';
import 'task_mutations.dart';
import 'start_node.dart';
import 'goal_node.dart';
import 'confetti_shapes.dart';

class WishNodeMap extends StatefulWidget {
	final WishModel wish;
	final Future<void> Function(String wishId, String taskId) onCompleteTask;
	final Future<void> Function(String wishId, String taskId, String newTitle, bool newRepeat) onEditTask;
	final Future<void> Function(String wishId, String taskId)? onRemoveTask;
	final Future<String> Function(String wishId, String phaseId, String newTitle, bool newRepeat)? onAddTask;
	final VoidCallback? onRegenerateShorterPhase;
	final String userId;
	final Future<void> Function(String wishId, String taskId)? onUncompleteTask;
  final VoidCallback? onWishCompleted;
  final void Function(TaskModel task)? onAddTaskCommitted;
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
    this.onWishCompleted,
    this.onAddTaskCommitted
	}) : super(key: key);

	@override
	_WishNodeMapState createState() => _WishNodeMapState();
}

class _WishNodeMapState extends State<WishNodeMap> with TickerProviderStateMixin {
	late WishModel wish;
	late CelebrationService _celebration;
  Timer? _refreshTimer;

	String? completingTaskId;
	Map<String, AnimationController> _controllers = {};

	// Phase animation controllers (for "all tasks completed" celebration)
	Map<String, AnimationController> _phaseControllers = {};
	Map<String, bool> _phaseWasCompleted = {};

	// repeat task state & logic extracted
	late RepeatTaskService _repeatService;

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

		// prepare controllers for tasks (for completion pulse) and phase controllers
		for (var p in wish.phases) {
			_phaseControllers[p.id] = AnimationController(vsync: this, duration: Duration(milliseconds: 700));
			_phaseWasCompleted.putIfAbsent(p.id, () => _isPhaseCompleted(p));
			for (var t in p.tasks) {
				_controllers[t.id] = AnimationController(vsync: this, duration: Duration(milliseconds: 450));
			}
		}

		// init repeat-task service and seed it from wish
		_repeatService = RepeatTaskService(defaultCooldown: Duration(minutes: 1));
		for (var p in wish.phases) {
			for (var t in p.tasks) {
				_repeatService.initForTask(t.id, initialCount: (t.repeatedAmount ?? 0));
			}
		}

		// confetti init
		_confettiController = ConfettiController(duration: Duration(seconds: 5));

		// celebration helper (keeps confetti/phase chaining here)
		_celebration = CelebrationService(
			phaseControllers: _phaseControllers,
			confettiController: _confettiController,
			perPhaseHold: Duration(milliseconds: 200),
			phaseStagger: _phaseStagger,
		);

		_wishCelebrated = false;
		
		// Timer to refresh UI every second to update visual states
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
				if (mounted) {
					setState(() {
						// Trigger rebuild to update visual states
					});
				}
      },
    );

	}

	@override
	void didUpdateWidget(covariant WishNodeMap oldWidget) {
		super.didUpdateWidget(oldWidget);
		if (oldWidget.wish.id != widget.wish.id) {
			// dispose removed controllers
			final oldTaskIds = oldWidget.wish.phases.expand((p) => p.tasks.map((t) => t.id)).toSet();
			final newTaskIds = widget.wish.phases.expand((p) => p.tasks.map((t) => t.id)).toSet();

			for (final removedId in oldTaskIds.difference(newTaskIds)) {
				_controllers[removedId]?.dispose();
				_controllers.remove(removedId);
				_repeatService.removeTask(removedId);
			}

			// create controllers for new tasks, seed repeat service
			for (final newId in newTaskIds.difference(oldTaskIds)) {
				_controllers[newId] = AnimationController(vsync: this, duration: Duration(milliseconds: 450));
				final matching = widget.wish.phases
					.expand((p) => p.tasks)
					.firstWhere((tt) => tt.id == newId, orElse: () => TaskModel(id: "null", text: "something went wrong", phaseId: "somthing went wron"));
				_repeatService.initForTask(newId, initialCount: (matching.repeatedAmount ?? 0));
			}

			// phase controllers
			final oldPhaseIds = oldWidget.wish.phases.map((p) => p.id).toSet();
			final newPhaseIds = widget.wish.phases.map((p) => p.id).toSet();

			for (final removed in oldPhaseIds.difference(newPhaseIds)) {
				_phaseControllers[removed]?.dispose();
				_phaseControllers.remove(removed);
				_phaseWasCompleted.remove(removed);
			}

			for (final added in newPhaseIds.difference(oldPhaseIds)) {
				_phaseControllers[added] = AnimationController(vsync: this, duration: Duration(milliseconds: 700));
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
    _refreshTimer?.cancel();
		super.dispose();
	}

	int _visuallyCompletedTaskCount() {
		int count = 0;
		for (final p in wish.phases) {
			for (final t in p.tasks) {
				if (_isTaskVisuallyComplete(t)) {
					count++;
				}
			}
		}
		return count;
	}
	
	bool _isTaskVisuallyComplete(TaskModel t) {
		final state = _visualStateForTask(t);
		return state == TaskVisualState.completed;
	}

  int _totalTaskCount() {
    return wish.phases.fold(
      0,
      (sum, p) => sum + p.tasks.length,
    );
  }

	bool _isRepeatTaskDue(TaskModel t) {
		return _repeatService.isDue(t.id);
	}

	TaskModel? _findCurrentTask() {
		for (var p in wish.phases) {
			for (var t in p.tasks) {
				final isDue = _isRepeatTaskDue(t);
				if (!t.completed || (t.completed && t.repeat == true && isDue)) {
					return t;
				}
			}
		}
		return null;
	}

	bool _isPhaseCompleted(PhaseModel p) {
		if (p.tasks.isEmpty) return false;
		return p.tasks.every((t) => t.completed == true);
	}

	Future<void> _handleComplete(TaskModel task) async {
		// due check via service
		if (task.repeat == true && !_isRepeatTaskDue(task)) {
			final next = _repeatService.nextAvailableAt(task.id);
			final s = next != null ? next.toLocal().toString() : 'later';
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Task not due until $s')));
			return;
		}

		if (task.completed || completingTaskId != null) {
			if (task.completed && task.repeat != true) return;
		}

		setState(() => completingTaskId = task.id);
		final controller = _controllers[task.id];
		if (controller != null) controller.forward(from: 0.0);

		try {
			await widget.onCompleteTask(wish.id, task.id);

			// optimistic local update
      setState(() {
        task.completed = true;
        task.completedAt = DateTime.now();

        if (task.repeat == true) {
          _repeatService.applyCompletion(task.id);

          // 🔔 THIS is what drives the UI + animation
          task.repeatedAmount = (task.repeatedAmount ?? 0) + 1;
        }
      });

			if (controller != null) await controller.reverse();

			final phase = wish.phases.firstWhere((p) => p.tasks.any((tt) => tt.id == task.id), orElse: () => PhaseModel(id: 'null', title: '', tasks: []));
			if (phase.id != 'null') {
				final completedNow = _isPhaseCompleted(phase);
				final wasCompleted = _phaseWasCompleted[phase.id] ?? false;
				if (completedNow && !wasCompleted) {
					final isLastPhase = wish.phases.isNotEmpty && wish.phases.last.id == phase.id;
					final allPhasesComplete = wish.phases.every((pp) => pp.tasks.isNotEmpty && pp.tasks.every((tt) => tt.completed == true));

					if (isLastPhase && allPhasesComplete && !_wishCelebrated) {
            _wishCelebrated = true;

            await _celebration.celebrateAllPhasesSequential(
              wish.phases.map((p) => p.id).toList(),
              finalPhaseFirst: true,
            );

            widget.onWishCompleted?.call();

            for (final p in wish.phases) {
              _phaseWasCompleted[p.id] = true;
            }
          }
				}
			}
		} catch (e) {
			if (controller != null) {
				controller.forward(from: 0.0).then((_) => controller.reverse());
			}
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to complete task')));
			print('onCompleteTask failed: $e');
		} finally {
			setState(() => completingTaskId = null);
		}
	}

  TaskVisualState _visualStateForTask(TaskModel t) {
		// Never completed
		if (t.completedAt == null) {
			return TaskVisualState.neverCompleted;
		}

		// Non-repeat tasks
		if (t.repeat != true) {
			return t.completed
				? TaskVisualState.completed
				: TaskVisualState.neverCompleted;
		}

		// Repeat tasks
		final bool due = _isRepeatTaskDue(t);

		if (t.completed && !due) {
			// Just completed, cooling down
			return TaskVisualState.completed;
		}

		// Due again → semi / hollow state
		return TaskVisualState.repeatReady;
	}

	Future<void> _addTaskToPhase(int phaseIndex, PhaseModel phase, BuildContext ctx) async {
		// delegate heavy-lifting to task_mutations helper which returns the created task (optimistic)
		final newTask = await TaskMutations.addTaskToPhase(
			context: ctx,
			phase: phase,
			wishId: wish.id,
			onCreateLocal: (TaskModel t) {
				setState(() {
					phase.tasks.add(t);
					_controllers[t.id] =
						AnimationController(vsync: this, duration: Duration(milliseconds: 450));
					_repeatService.initForTask(t.id, initialCount: 0);
				});
			},
			onPersist: widget.onAddTask ??
				(_, __, ___, ____) async {
					throw Exception('onAddTask not wired');
				},
		);
	}

	Future<void> _handleUncomplete(TaskModel task) async {
		final wasCompleted = task.completed;
		final oldCompletedAt = task.completedAt;
		setState(() {
			task.completed = false;
			task.completedAt = null;
		});

		final phase = wish.phases.firstWhere((p) => p.tasks.any((tt) => tt.id == task.id), orElse: () => PhaseModel(id: 'null', title: '', tasks: []));
		if (phase.id != 'null') {
			_phaseWasCompleted[phase.id] = false;
		}
		_wishCelebrated = false;

		if (widget.onUncompleteTask != null) {
			try {
				await widget.onUncompleteTask!(wish.id, task.id);
			} catch (e) {
				setState(() {
					task.completed = wasCompleted;
					task.completedAt = oldCompletedAt;
				});
				ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to un-complete task')));
				print('onUncompleteTask failed: $e');
				return;
			}
		}
	}

	Future<void> _removeTaskConfirmed(String taskId) async {
		// remove locally, but keep helper to call parent persistence if present
		await TaskMutations.removeTaskConfirmed(
			wish: wish,
			taskId: taskId,
			onLocalRemove: () {
				setState(() {
					_controllers[taskId]?.dispose();
					_controllers.remove(taskId);
					_repeatService.removeTask(taskId);
				});
			},
			onRecalcPhase: () {
				setState(() {
					for (final p in wish.phases) {
						_phaseWasCompleted[p.id] = _isPhaseCompleted(p);
					}
				});
			},
			onPersistRemove: widget.onRemoveTask,
		);
	}

	Path _drawStarPath(Size size) => ConfettiShapes.drawStarPath(size);

	@override
	Widget build(BuildContext context) {
		final phases = wish.phases;
		return Stack(
			children: [
				Container(
					color: Palette.darkest,
					padding: EdgeInsets.only(top: 18, left: 18, right: 18),
					child: LayoutBuilder(builder: (context, constraints) {
						final totalHeight = constraints.maxHeight;
						final headerReserve = 140.0;
						final tasksHeight = (totalHeight - headerReserve).clamp(100.0, totalHeight);

						return SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: Row(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									SizedBox(
										width: 220,
										child: Column(
											children: [
												StartNode(wish: wish, current: _findCurrentTask()),
												SizedBox(height: 18),
											],
										),
									),
									SizedBox(width: 28),

									for (int i = 0; i < phases.length; i++)
										PhaseColumn(
											phase: phases[i],
											phaseIndex: i + 1,
											tasksHeight: tasksHeight,
											celebrationScale: _phaseControllers[phases[i].id] != null
												? Tween(begin: 0.6, end: 1.12).animate(CurvedAnimation(parent: _phaseControllers[phases[i].id]!, curve: Curves.elasticOut))
												: null,
											celebrationFade: _phaseControllers[phases[i].id] != null
												? Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _phaseControllers[phases[i].id]!, curve: Curves.easeOut))
												: null,
											taskBuilder: (context, t) => TaskTile(
												task: t,
												isCurrent: _findCurrentTask()?.id == t.id,
												visualState: _visualStateForTask(t),
												onComplete: (!t.completed || (t.repeat == true && _isRepeatTaskDue(t)))
													? () => _handleComplete(t)
													: null,
												onUncomplete: (t.completed && t.repeat != true)
													? () => _handleUncomplete(t)
													: null,
												onEdit: () async {
													// unchanged
												},
												onRemove: () => _removeTaskConfirmed(t.id),
												scaleAnim: _controllers[t.id] != null
													? Tween(begin: 1.0, end: 1.08).animate(
															CurvedAnimation(
																parent: _controllers[t.id]!,
																curve: Curves.easeOut,
															),
														)
													: null,
											),
											onAddPressed: () => _addTaskToPhase(i, phases[i], context),
										),

									SizedBox(width: 28),
									SizedBox(width: 220, child: GoalNode(wish: wish)),
								],
							),
						);
					}),
				),

				Positioned(
					child: ConfettiOverlay(controller: _confettiController, createParticlePath: _drawStarPath),
				),
			],
		);
	}
}