import 'package:flutter/material.dart';
import 'package:wishnode/widgets/goal_input.dart';
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
						Text(subtitle, style: TextStyle(color: Palette.dampTitles, fontSize: 12)),
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
				color: Palette.signatureGreen,
				borderRadius: BorderRadius.circular(8),
				boxShadow: [BoxShadow(color: Palette.signatureGreen.withOpacity(0.18), blurRadius: 6, offset: Offset(0, 4))],
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
            colors: [Palette.signatureGreen.withOpacity(1.0), Palette.signatureGreen.withOpacity(0.85)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: [BoxShadow(color: Palette.darkest, blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: Center(
          child: Text('+', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ),
    );
  }
}

class GoalInputSection extends StatefulWidget {
	final TextEditingController controller;
	final FocusNode focusNode;
	final bool loading;
	final Future<void> Function(String? context) onSubmitted;
	final VoidCallback? onClose;

	const GoalInputSection({
		super.key,
		required this.controller,
		required this.focusNode,
		required this.loading,
		required this.onSubmitted,
		required this.onClose,
	});

	@override
	State<GoalInputSection> createState() => _GoalInputSectionState();
}

class _GoalInputSectionState extends State<GoalInputSection> {
	bool _showContext = false;
	final TextEditingController _contextController = TextEditingController();

	@override
	void dispose() {
		_contextController.dispose();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		return Container(
			decoration: BoxDecoration(
				borderRadius: BorderRadius.circular(24),
				boxShadow: [
					BoxShadow(
						color: Palette.darkest,
						blurRadius: 24,
						offset: Offset(0, 12),
					),
				],
			),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				children: [
					Row(
						children: [
							Expanded(
								child: Text(
									'What do you want to achieve?',
									style: TextStyle(
										fontSize: 22,
										color: Palette.ourWhite,
										fontWeight: FontWeight.w600,
									),
								),
							),
							if (widget.onClose != null)
								IconButton(
									onPressed: widget.onClose,
									icon: Icon(Icons.close, size: 18, color: Color(0xFF9AA0A8)),
									padding: EdgeInsets.zero,
									constraints: BoxConstraints(),
									tooltip: 'Hide',
								),
						],
					),

					SizedBox(height: 12),

					GoalInput(
						controller: widget.controller,
						focusNode: widget.focusNode,
						loading: widget.loading,
						onSubmitted: () async {
							final contextText = _showContext && _contextController.text.trim().isNotEmpty
								? _contextController.text.trim()
								: null;

							await widget.onSubmitted(contextText);
						},
						width: 640,
					),

					SizedBox(height: 8),

					Align(
						alignment: Alignment.centerLeft,
						child: TextButton(
							style: TextButton.styleFrom(
								foregroundColor: Palette.ourWhite,
								padding: EdgeInsets.zero,
							),
							onPressed: () {
								setState(() {
									_showContext = !_showContext;
								});
							},
							child: Text(
								_showContext ? 'Hide context' : 'Add context',
								style: TextStyle(fontWeight: FontWeight.w500),
							),
						),
					),

					if (_showContext) ...[
						SizedBox(height: 8),
						ConstrainedBox(
							constraints: BoxConstraints(maxWidth: 640),
							child: Container(
								decoration: BoxDecoration(
									color: Palette.ourWhite,
									borderRadius: BorderRadius.circular(24),
								),
								child: Padding(
									padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
									child: TextField(
										controller: _contextController,
										maxLines: 5,
										style: TextStyle(
											color: Palette.darkest,
											fontSize: 15,
										),
										decoration: InputDecoration(
											border: InputBorder.none,
											hintText: 'What are your circumstances relative to this goal?',
											hintStyle: TextStyle(color: Palette.darkest),
										),
									),
								),
							),
						),
					],
				],
			),
		);
	}
}


class WishLimitModal extends StatefulWidget {
	final VoidCallback onDismiss;
	final Future<void> Function(String email)? onSubmit;

	const WishLimitModal({
		Key? key,
		required this.onDismiss,
		this.onSubmit,
	}) : super(key: key);

	@override
	State<WishLimitModal> createState() => _WishLimitModalState();
}

class _WishLimitModalState extends State<WishLimitModal> {
	final TextEditingController _controller = TextEditingController();
	bool _agreeToUpdates = false;

	@override
	void dispose() {
		_controller.dispose();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		final email = _controller.text.trim();
		final showConsent = email.isNotEmpty;

		return GestureDetector(
			onTap: widget.onDismiss,
			child: Material(
				color: Palette.darkest.withValues(alpha: 15),
				child: Center(
					child: GestureDetector(
						onTap: () {},
						child: Container(
							width: 420,
							padding: const EdgeInsets.all(24),
							decoration: BoxDecoration(
								color: Palette.card,
								borderRadius: BorderRadius.circular(16),
							),
							child: Column(
								mainAxisSize: MainAxisSize.min,
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									Text(
										'You already have 3 active wishes',
										style: TextStyle(
											fontSize: 20,
											fontWeight: FontWeight.w700,
											color: Palette.ourWhite,
										),
									),
									const SizedBox(height: 12),
									Text(
										'To create a new wish, complete or delete an existing one — or leave your email and I can unlock higher limits as the project grows.',
										style: TextStyle(
											fontSize: 14,
											color: Palette.ourWhite,
										),
									),
									const SizedBox(height: 20),
									TextField(
										controller: _controller,
										onChanged: (_) {
											setState(() {
												// reset consent if email is cleared
												if (_controller.text.trim().isEmpty) {
													_agreeToUpdates = false;
												}
											});
										},
										style: TextStyle(color: Palette.ourWhite),
										decoration: InputDecoration(
											labelText: 'Email',
											labelStyle: TextStyle(color: Palette.ourWhite),
											hintStyle: TextStyle(
												color: Palette.ourWhite.withOpacity(0.6),
											),
										),
										keyboardType: TextInputType.emailAddress,
									),

									if (showConsent) ...[
										const SizedBox(height: 12),
										Row(
											children: [
												Checkbox(
													value: _agreeToUpdates,
													onChanged: (v) {
														setState(() {
															_agreeToUpdates = v == true;
														});
													},
													activeColor: Palette.signatureGreen,
													checkColor: Palette.darkest,
												),
												Expanded(
													child: Text(
														'I agree to receive updates about Wishnode',
														style: TextStyle(
															color: Palette.ourWhite,
															fontSize: 13,
														),
													),
												),
											],
										),
									],

									const SizedBox(height: 24),
									Row(
										mainAxisAlignment: MainAxisAlignment.end,
										children: [
											TextButton(
												onPressed: widget.onDismiss,
												child: Text(
													'Close',
													style: TextStyle(color: Palette.ourWhite),
												),
											),
											const SizedBox(width: 8),
											ElevatedButton(
												onPressed: widget.onSubmit == null ||
														(showConsent && !_agreeToUpdates)
													? null
													: () async {
															final email = _controller.text.trim();
															if (email.isEmpty) return;
															await widget.onSubmit!(email);
														},
												style: ElevatedButton.styleFrom(
													foregroundColor: Palette.signatureGreen,
												),
												child: const Text('Notify me'),
											),
										],
									),
								],
							),
						),
					),
				),
			),
		);
	}
}
