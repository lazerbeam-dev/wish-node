import 'package:flutter/material.dart';
import '../ui/pallet.dart';
class ItemCard extends StatelessWidget {
	final Map<String, dynamic> item;

	// thresholds mapping: minLegendariness -> visual style
	static const List<_LegendStyle> _legendStyles = [
		_LegendStyle(min: 0, color: Palette.ourWhite, overlay: Icons.circle, glow: 0.0),
		_LegendStyle(min: 30, color: Palette.signatureGreen, overlay: Icons.star_border, glow: 4.0),
		_LegendStyle(min: 60, color: Palette.brightCta, overlay: Icons.workspace_premium, glow: 8.0),
		_LegendStyle(min: 90, color: Palette.accent, overlay: Icons.emoji_events, glow: 14.0),
	];

	const ItemCard({super.key, required this.item});

	_LegendStyle _styleFor(int value) {
		_LegendStyle chosen = _legendStyles.first;
		for (final s in _legendStyles) {
			if (value >= s.min) chosen = s;
		}
		return chosen;
	}

	@override
	Widget build(BuildContext context) {
		final String name = (item['title'] ?? item['name'] ?? '') as String;
		final String description = (item['description'] ?? '') as String;
		final String emoji = (item['emoji'] ?? '') as String;
		final String emojiAccent = (item['emoji_accent'] ?? '') as String;
		final int leg = (item['legendariness'] ?? 0) as int;
		final style = _styleFor(leg);

		return SizedBox(
			height: 110,
			child: Stack(
				alignment: Alignment.center,
				children: [
					// glowing frame / background
					Container(
						margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
						decoration: BoxDecoration(
							gradient: LinearGradient(
								colors: [
									Palette.card,
                  Palette.card.withAlpha(100),
								],
								begin: Alignment.topLeft,
								end: Alignment.bottomRight,
							),
							borderRadius: BorderRadius.circular(14),
							boxShadow: style.glow > 0
								? [
										BoxShadow(
											color: style.color.withOpacity(0.20),
											blurRadius: style.glow,
											spreadRadius: style.glow * 0.14,
										)
									]
								: [],
							border: Border.all(
								color: style.color.withOpacity(0.88),
								width: 1.6,
							),
						),
					),

					// Card content
					Positioned.fill(
						child: Padding(
							padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
							child: Row(
								children: [
									// Emoji badge as a Stack so we can overlay accent
									Container(
										width: 84,
										height: 84,
										child: Stack(
											children: [
												// background rounded square
												Positioned.fill(
													child: Container(
														decoration: BoxDecoration(
															borderRadius: BorderRadius.circular(12),
															color: Palette.ourWhite.withOpacity(0.04),
														),
													),
												),

												// main emoji (center)
												Positioned.fill(
													child: Center(
														child: Text(
															emoji,
															style: const TextStyle(fontSize: 40),
														),
													),
												),

												// small accent positioned bottom-right
												Positioned(
													right: 6,
													bottom: 6,
													child: Container(
														width: 28,
														height: 28,
														child: Center(
															child: Text(
																emojiAccent,
																style: const TextStyle(fontSize: 14),
															),
														),
													),
												),
											],
										),
									),

									const SizedBox(width: 12),

									// Name + description
									Expanded(
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											mainAxisAlignment: MainAxisAlignment.center,
											children: [
												Tooltip(
	message: name,
	waitDuration: Duration(milliseconds: 400),
	showDuration: Duration(seconds: 6),
	preferBelow: false,
	textStyle: TextStyle(
		color: Palette.ourWhite,
		fontSize: 14,
		fontWeight: FontWeight.w600,
	),
	decoration: BoxDecoration(
		color: Palette.card,
		borderRadius: BorderRadius.circular(8),
		border: Border.all(color: Palette.ourWhite.withOpacity(0.2)),
	),
	child: Text(
		name,
		style: TextStyle(
			fontSize: 16,
			fontWeight: FontWeight.w700,
			color: Palette.ourWhite.withOpacity(0.95),
		),
		maxLines: 1,
		overflow: TextOverflow.ellipsis,
	),
),

												Tooltip(
	message: description,
	waitDuration: Duration(milliseconds: 400),
	showDuration: Duration(seconds: 6),
	preferBelow: false,
	textStyle: TextStyle(
		color: Palette.ourWhite,
		fontSize: 12,
	),
	decoration: BoxDecoration(
		color: Palette.card,
		borderRadius: BorderRadius.circular(8),
		border: Border.all(color: Palette.ourWhite.withOpacity(0.2)),
	),
	child: Text(
		description,
		style: TextStyle(
			fontSize: 12,
			color: Palette.ourWhite.withOpacity(0.78),
		),
		maxLines: 2,
		overflow: TextOverflow.ellipsis,
	),
),

											],
										),
									),

									const SizedBox(width: 8),

									// right-side small legend badge
									Column(
										mainAxisAlignment: MainAxisAlignment.center,
										children: [
						// 					Container(
						// 	padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
						// 	decoration: BoxDecoration(
						// 		color: style.color,
						// 		borderRadius: BorderRadius.circular(8),
						// 	),
						// 	child: Row(
						// 		children: [
						// 			Icon(style.overlay, size: 14, color: Colors.white),
						// 			const SizedBox(width: 6),
						// 			Text(
						// 				'',
						// 				style: const TextStyle(color: Colors.white, fontSize: 12),
						// 			),
						// 		],
						// 	),
						// )
										],
									),
								],
							),
						),
					),

					// top-left tiny ribbon showing rarity color (purely visual)
					Positioned(
						right: 8,
						top: 8,
						child: Container(
							padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
							decoration: BoxDecoration(
								color: style.color,
								borderRadius: BorderRadius.circular(8),
							),
							child: Row(
								children: [
									Icon(style.overlay, size: 14, color: Palette.ourWhite),
									const SizedBox(width: 6),
									Text(
										'',
										style: const TextStyle(color: Palette.ourWhite, fontSize: 12),
									),
								],
							),
						),
					),
				],
			),
		);
	}
}

class _LegendStyle {
	final int min;
	final Color color;
	final IconData overlay;
	final double glow;

	const _LegendStyle({
		required this.min,
		required this.color,
		required this.overlay,
		required this.glow,
	});
}
