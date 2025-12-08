import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';
import '../models/wish_models.dart';

class GoalNode extends StatelessWidget {
	final WishModel wish;

	const GoalNode({Key? key, required this.wish}) : super(key: key);

	@override
	Widget build(BuildContext context) {
		return SizedBox(
			height: 400,
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
										Text(wish.title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
									],
								),
							),
						],
					),
				),
			),
		);
	}
}
