// lib/widgets/wish_node_map/task_tile.dart
import 'package:flutter/material.dart';
import '../../ui/pallet.dart';
import '../../models/wish_models.dart';

class TaskTile extends StatelessWidget {
	final TaskModel task;
	final bool isCurrent;
	final bool displayDone; // computed by parent
	final VoidCallback? onComplete;
	final VoidCallback? onEdit;
	final VoidCallback? onRemove;
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
	});

	@override
	Widget build(BuildContext context) {
		final tile = AnimatedContainer(
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
						onTap: onComplete,
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
								child: displayDone ? Icon(Icons.check, size: 18, color: Colors.black) : Icon(Icons.radio_button_unchecked, size: 18, color: Palette.muted),
							),
						),
					),
					const SizedBox(width: 12),
					Expanded(
						child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
							Text(task.text, style: TextStyle(color: Colors.white, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500)),
							const SizedBox(height: 4),
							Row(children: [
								if (task.repeat == true) ...[
									Icon(Icons.repeat, size: 14, color: Palette.accent),
									const SizedBox(width: 6),
									Text('repeat', style: TextStyle(color: Palette.muted, fontSize: 12)),
								],
								if (displayDone) ...[
									const SizedBox(width: 8),
									Text('done', style: TextStyle(color: Palette.good, fontSize: 12, fontWeight: FontWeight.w700))
								]
							]),
						]),
					),
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
											onTap: () { Navigator.of(context).pop(); if (onEdit != null) onEdit!(); },
										),
										if (task.completed) ListTile(
											leading: Icon(Icons.undo, color: Colors.white),
											title: Text('Mark as incomplete', style: TextStyle(color: Colors.white)),
											onTap: () { Navigator.of(context).pop(); if (onEdit != null) onEdit!(); },
										),
										ListTile(
											leading: Icon(Icons.delete, color: Palette.danger),
											title: Text('Remove', style: TextStyle(color: Palette.danger)),
											onTap: () { Navigator.of(context).pop(); if (onRemove != null) onRemove!(); },
										),
									]),
								);
							});
						},
					)
				],
			),
		);

		if (scaleAnim != null) {
			return ScaleTransition(scale: scaleAnim!, child: tile);
		}
		return tile;
	}
}
