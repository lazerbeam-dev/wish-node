import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';
import '../models/wish_models.dart';
import 'package:wishnode/widgets/stateless_widgets.dart';

class StartNode extends StatelessWidget {
	final WishModel wish;
	final TaskModel? current;

	const StartNode({Key? key, required this.wish, required this.current}) : super(key: key);

	@override
	Widget build(BuildContext context) {
		return SizedBox(
			height: 400, // container callers will usually bound this
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
								color: Palette.signatureGreen,
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
										Text(wish.title, style: TextStyle(color: Palette.ourWhite, fontWeight: FontWeight.w600)),
										if (current != null) ...[
											SizedBox(height: 6),
											Row(
												children: [
													Icon(Icons.whatshot, size: 14, color: Palette.accent),
													SizedBox(width: 6),
													Expanded(child: Text(current!.text, style: TextStyle(color: Palette.dampTitles, fontSize: 12))),
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
}
