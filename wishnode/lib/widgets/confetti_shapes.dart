import 'dart:ui';
import 'dart:math';

class ConfettiShapes {
	static Path drawStarPath(Size size) {
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
			if (i == 0)
				path.moveTo(x, y);
			else
				path.lineTo(x, y);
			rotation += step;
		}
		path.close();
		return path;
	}
}
