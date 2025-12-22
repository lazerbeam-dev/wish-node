// lib/widgets/wish_node_map/task_tile.dart
import 'package:flutter/material.dart';
import '../../ui/pallet.dart';
import '../../models/wish_models.dart';

enum TaskVisualState {
	neverCompleted,
	completed,
	repeatReady,
}

class TaskTile extends StatelessWidget {
	final TaskModel task;
	final bool isCurrent;
	final TaskVisualState visualState;
	final VoidCallback? onComplete;
	final VoidCallback? onEdit;
	final VoidCallback? onRemove;
	final VoidCallback? onUncomplete;
	final Animation<double>? scaleAnim;

	const TaskTile({
		super.key,
		required this.task,
		required this.isCurrent,
		required this.visualState,
		this.onComplete,
		this.onEdit,
		this.onRemove,
		this.scaleAnim,
		this.onUncomplete,
	});

	@override
	Widget build(BuildContext context) {
		final bool isRepeatTask = task.repeat == true;
		
		// Determine display state based on visualState
		final bool showAsDone = visualState == TaskVisualState.completed;
		final bool hasEverBeenCompleted = visualState != TaskVisualState.neverCompleted;

		final tile = AnimatedContainer(
			duration: Duration(milliseconds: 220),
			padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
			decoration: BoxDecoration(
				color: Palette.darkest,
			),
			child: Row(
				children: [
					GestureDetector(
						onTap: onComplete,
						child: SizedBox(
							width: 36,
							height: 36,
							child: !hasEverBeenCompleted
								// A) NEVER COMPLETED
								? AnimatedContainer(
										duration: Duration(milliseconds: 220),
										decoration: BoxDecoration(
											shape: BoxShape.circle,
											border: Border.all(
												color: Palette.dampTitles.withOpacity(0.35),
												width: 2,
											),
										),
										child: Center(
											child: Icon(
												Icons.radio_button_unchecked,
												size: 18,
												color: Palette.dampTitles,
											),
										),
									)
								// B) COMPLETED / REPEAT STATES
								: Stack(
										alignment: Alignment.center,
										children: [
											// OUTER RING
											AnimatedContainer(
												duration: Duration(milliseconds: 220),
												width: 36,
												height: 36,
												decoration: BoxDecoration(
													shape: BoxShape.circle,
													color: (showAsDone || visualState == TaskVisualState.repeatReady)
														? Palette.signatureGreen
														: Colors.transparent,
													border: Border.all(
														color: Palette.signatureGreen,
														width: 2,
													),
												),
											),

											// INNER STATE
											AnimatedContainer(
												duration: Duration(milliseconds: 220),
												width: 18,
												height: 18,
												decoration: BoxDecoration(
													shape: BoxShape.circle,
													color: showAsDone
														? Palette.signatureGreen.withOpacity(0.85)
														: Palette.card,
												),
												child: showAsDone
													? Icon(
															Icons.check,
															size: 14,
															color: Colors.black,
														)
													: null,
											),
										],
									),
						),
					),

					const SizedBox(width: 12),

					Expanded(
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
								Text(
									task.text,
									style: TextStyle(
										color: Colors.white,
										fontWeight:
											isCurrent ? FontWeight.w700 : FontWeight.w500,
									),
								),
								const SizedBox(height: 4),
								Row(
									children: [
										if (isRepeatTask) ...[
											Icon(Icons.repeat,
												size: 14, color: Palette.accent),
											const SizedBox(width: 6),
											AnimatedSwitcher(
												duration: Duration(milliseconds: 260),
												child: Text(
													task.repeatedAmount != null &&
															task.repeatedAmount! > 0
														? 'repeat ×${task.repeatedAmount}'
														: 'repeat',
													key: ValueKey(task.repeatedAmount),
													style: TextStyle(
														color: Palette.dampTitles,
														fontSize: 12,
													),
												),
											),
										],
										if (showAsDone) ...[
											const SizedBox(width: 8),
											Text(
												'done',
												style: TextStyle(
													color: Palette.signatureGreen,
													fontSize: 12,
													fontWeight: FontWeight.w700,
												),
											),
										],
									],
								),
							],
						),
					),

					IconButton(
						icon: Icon(Icons.more_horiz, color: Palette.dampTitles),
						onPressed: () {
							showModalBottomSheet(
								context: context,
								backgroundColor: Palette.darkest,
								builder: (_) {
									return Padding(
										padding: EdgeInsets.all(12),
										child: Column(
											mainAxisSize: MainAxisSize.min,
											children: [
												ListTile(
													leading: Icon(Icons.edit,
														color: Palette.ourWhite),
													title: Text('Edit task',
														style: TextStyle(color: Colors.white)),
													onTap: () {
														Navigator.of(context).pop();
														onEdit?.call();
													},
												),
												if (task.completed)
													ListTile(
														leading: Icon(Icons.undo,
															color: Palette.ourWhite),
														title: Text(
															'Mark as incomplete',
															style: TextStyle(color: Colors.white),
														),
														onTap: () {
															Navigator.of(context).pop();
															onUncomplete?.call();
														},
													),
												ListTile(
													leading: Icon(Icons.delete,
														color: Palette.ourWhite),
													title: Text('Remove',
														style: TextStyle(color: Palette.ourWhite)),
													onTap: () {
														Navigator.of(context).pop();
														onRemove?.call();
													},
												),
											],
										),
									);
								},
							);
						},
					),
				],
			),
		);

		if (scaleAnim != null) {
			return ScaleTransition(scale: scaleAnim!, child: tile);
		}
		return tile;
	}
}