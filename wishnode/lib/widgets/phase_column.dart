// lib/widgets/wish_node_map/phase_column.dart
import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';
import 'package:wishnode/widgets/stateless_widgets.dart';
import '../../models/wish_models.dart';

typedef TaskBuilder = Widget Function(BuildContext context, TaskModel task);

class PhaseColumn extends StatelessWidget {
	final PhaseModel phase;
	final int phaseIndex;
	final double tasksHeight;
	final TaskBuilder taskBuilder;
	final VoidCallback onAddPressed;
	final Animation<double>? celebrationScale;
	final Animation<double>? celebrationFade;

	const PhaseColumn({
		super.key,
		required this.phase,
		required this.phaseIndex,
		required this.tasksHeight,
		required this.taskBuilder,
		required this.onAddPressed,
		this.celebrationScale,
		this.celebrationFade,
	});

	@override
	Widget build(BuildContext context) {
		final borderRadius = BorderRadius.circular(14);

		return Stack(
			clipBehavior: Clip.none,
			children: [
				SizedBox(
					width: 320,
					//height: tasksHeight + 120, // fixed phase height
					child: Container(
						margin: EdgeInsets.only(top: 12, left: 8, right: 8),
						padding: EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 12),
						decoration: BoxDecoration(
							color: Palette.card,
							borderRadius: borderRadius,
							boxShadow: [
								BoxShadow(
									color: Palette.darkest,
									blurRadius: 8,
									offset: Offset(0, 4),
								),
							],
						),
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
								// HEADER
								Row(
									children: [
										PhaseDot(index: phaseIndex),
										SizedBox(width: 10),
										Expanded(
											child: Text(
												phase.title,
												style: TextStyle(
													color: Palette.ourWhite,
													fontWeight: FontWeight.w700,
												),
											),
										),
										SizedBox(width: 8),
										Text(
											'${phase.tasks.where((t) => t.completed).length}/${phase.tasks.length}',
											style: TextStyle(color: Palette.dampTitles),
										),
									],
								),

								SizedBox(height: 10),

								// TASKS (scrollable, bounded)
								Flexible(
	fit: FlexFit.loose,
	child: Container(
		decoration: BoxDecoration(
			color: Palette.darkest,
			borderRadius: BorderRadius.circular(16),
		),
		padding: EdgeInsets.all(10),
		child: ListView.builder(
			shrinkWrap: true,
			physics: phase.tasks.length <= 4
				? NeverScrollableScrollPhysics()
				: AlwaysScrollableScrollPhysics(),
											//physics: AlwaysScrollableScrollPhysics(),
											itemCount: phase.tasks.length,
											itemBuilder: (context, idx) {
												final t = phase.tasks[idx];
												return Padding(
													padding: EdgeInsets.only(left: 2, right: 2),
													child: KeyedSubtree(
														key: ValueKey(t.id),
														child: taskBuilder(context, t),
													),
												);
											},
										),
									),
								),

								// ADD BUTTON (pinned bottom, same level across phases)
								SizedBox(height: 10),
								Center(
									child: AddTaskButton(onPressed: onAddPressed),
								),
							],
						),
					),
				),

				// CELEBRATION OVERLAY
				if (celebrationFade != null && celebrationScale != null)
					Positioned.fill(
						child: IgnorePointer(
							child: Center(
								child: FadeTransition(
									opacity: celebrationFade!,
									child: ScaleTransition(
										scale: celebrationScale!,
										child: Container(
											padding: EdgeInsets.all(6),
											decoration: BoxDecoration(
												shape: BoxShape.circle,
												gradient: LinearGradient(
													colors: [
														Palette.signatureGreen.withOpacity(0.95),
														Palette.accent.withOpacity(0.95),
													],
												),
												boxShadow: [
													BoxShadow(
														color: Palette.signatureGreen.withOpacity(0.35),
														blurRadius: 18,
														spreadRadius: 6,
													),
												],
											),
											child: Icon(
												Icons.celebration,
												size: 44,
												color: Palette.darkest,
											),
										),
									),
								),
							),
						),
					),
			],
		);
	}
}
