import 'package:flutter/material.dart';
import '../ui/pallet.dart';
/// Small circular node used for start/goal
class NodeCircle extends StatelessWidget {
	final String label;
	final String subtitle;
	final Color color;
	final double size;
	final bool ring;

	const NodeCircle({
		Key? key,
		required this.label,
		required this.subtitle,
		required this.color,
		required this.size,
		this.ring = false,
	}) : super(key: key);

	@override
	Widget build(BuildContext context) {
		final inner = Container(
			width: size,
			height: size,
			decoration: BoxDecoration(
				shape: BoxShape.circle,
				gradient: LinearGradient(colors: [color.withOpacity(0.95), color.withOpacity(0.75)]),
				boxShadow: [BoxShadow(color: color.withOpacity(0.18), blurRadius: 12, offset: Offset(0, 8))],
			),
			child: Center(child: Icon(Icons.auto_awesome, color: Colors.white, size: size * 0.42)),
		);

		return Column(
			children: [
				if (ring)
					Container(
						padding: EdgeInsets.all(6),
						decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.28), width: 3)),
						child: inner,
					)
				else
					inner,
				SizedBox(height: 8),
				Column(
					children: [
						Text(label, style: TextStyle(color: Palette.accent, fontWeight: FontWeight.w700)),
						SizedBox(height: 2),
						Text(subtitle, style: TextStyle(color: Palette.muted, fontSize: 12)),
					],
				),
			],
		);
	}
}
/// Small phase dot with number
class PhaseDot extends StatelessWidget {
	final int index;
	const PhaseDot({Key? key, required this.index}) : super(key: key);
	@override
	Widget build(BuildContext context) {
		return Container(
			width: 28,
			height: 28,
			decoration: BoxDecoration(
				color: Palette.ring,
				borderRadius: BorderRadius.circular(8),
				boxShadow: [BoxShadow(color: Palette.ring.withOpacity(0.18), blurRadius: 6, offset: Offset(0, 4))],
			),
			child: Center(child: Text('$index', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
		);
	}
}

class AddTaskButton extends StatelessWidget {
  final VoidCallback onPressed;
  const AddTaskButton({Key? key, required this.onPressed}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Palette.good.withOpacity(1.0), Palette.good.withOpacity(0.85)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: Center(
          child: Text('+', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ),
    );
  }
}

