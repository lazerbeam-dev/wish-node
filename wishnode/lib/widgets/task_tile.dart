// lib/widgets/wish_node_map/task_tile.dart
import 'package:flutter/material.dart';
import '../../ui/pallet.dart';
import '../../models/wish_models.dart';

class TaskTile extends StatelessWidget {
	final TaskModel task;
	final bool isCurrent;
	final bool displayDone;
	final VoidCallback? onComplete;
	final VoidCallback? onEdit;
	final VoidCallback? onRemove;
	final VoidCallback? onUncomplete;
	final Animation<double>? scaleAnim;

	const TaskTile({
		super.key,
		required this.task,
		required this.isCurrent,
		required this.displayDone,
		this.onComplete,
		this.onEdit,
		this.onRemove,
		this.scaleAnim,
		this.onUncomplete,
	});

	@override
	Widget build(BuildContext context) {
		final tile = AnimatedContainer(
			duration: Duration(milliseconds: 220),
			padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
			decoration: BoxDecoration(
				color: displayDone ? Palette.card : Palette.darkest.withOpacity(0.02),
				borderRadius: BorderRadius.circular(10),
				border: Border.all(
					color: isCurrent
						? Palette.signatureGreen.withOpacity(0.9)
						: Colors.transparent,
					width: 1.5,
				),
			),
			child: Row(
				children: [
					GestureDetector(
						onTap: onComplete,
						child: AnimatedContainer(
							duration: Duration(milliseconds: 220),
							width: 36,
							height: 36,
							decoration: BoxDecoration(
								shape: BoxShape.circle,
								gradient: displayDone
									? LinearGradient(
											colors: [
												Palette.signatureGreen.withOpacity(0.9),
												Palette.signatureGreen.withOpacity(0.6),
											],
										)
									: null,
								border: Border.all(
									color: displayDone
										? Palette.signatureGreen
										: Palette.dampTitles.withOpacity(0.35),
								),
							),
							child: Center(
								child: displayDone
									? Icon(Icons.check, size: 18, color: Colors.black)
									: Icon(Icons.radio_button_unchecked,
											size: 18, color: Palette.dampTitles),
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
										if (task.repeat == true) ...[
											Icon(Icons.repeat,
												size: 14, color: Palette.accent),
											const SizedBox(width: 6),
											AnimatedSwitcher(
	duration: Duration(milliseconds: 260),
	transitionBuilder: (child, anim) {
		return ScaleTransition(
			scale: Tween(begin: 0.85, end: 1.0).animate(
				CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
			),
			child: FadeTransition(opacity: anim, child: child),
		);
	},
	child: Text(
		task.repeatedAmount != null && task.repeatedAmount! > 0
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
										if (displayDone) ...[
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
								backgroundColor: Palette.card,
								builder: (_) {
									return Padding(
										padding: const EdgeInsets.all(12.0),
										child: Column(
											mainAxisSize: MainAxisSize.min,
											children: [
												ListTile(
													leading:
														Icon(Icons.edit, color: Palette.ourWhite),
													title: Text(
														'Edit task',
														style: TextStyle(color: Colors.white),
													),
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
															style:
																TextStyle(color: Colors.white),
														),
														onTap: () {
															Navigator.of(context).pop();
															onUncomplete?.call();
														},
													),
												ListTile(
													leading: Icon(Icons.delete,
														color: Palette.ourWhite),
													title: Text(
														'Remove',
														style:
															TextStyle(color: Palette.ourWhite),
													),
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
