import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';

class FeedbackWidget extends StatefulWidget {
	final Future<void> Function(String text) onSubmit;
	final VoidCallback onClose;

	const FeedbackWidget({
		Key? key,
		required this.onSubmit,
		required this.onClose,
	}) : super(key: key);

	@override
	State<FeedbackWidget> createState() => _FeedbackWidgetState();
}

class _FeedbackWidgetState extends State<FeedbackWidget> {
	final TextEditingController _controller = TextEditingController();
	bool _submitting = false;

	@override
	void dispose() {
		_controller.dispose();
		super.dispose();
	}

	Future<void> _handleSubmit() async {
		final text = _controller.text.trim();
		if (text.isEmpty || _submitting) return;

		setState(() {
			_submitting = true;
		});

		await widget.onSubmit(text);
	}

	@override
	Widget build(BuildContext context) {
		return Material(
			color: Colors.black.withOpacity(0.55),
			child: Center(
				child: Container(
					width: 420,
					margin: const EdgeInsets.symmetric(horizontal: 16),
					padding: const EdgeInsets.all(20),
					decoration: BoxDecoration(
						color: Palette.card,
						borderRadius: BorderRadius.circular(18),
						boxShadow: [
							BoxShadow(
								color: Colors.black.withOpacity(0.4),
								blurRadius: 24,
								offset: const Offset(0, 12),
							),
						],
					),
					child: Column(
						mainAxisSize: MainAxisSize.min,
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							// Header
							Row(
								children: [
									Text(
										'Give feedback',
										style: TextStyle(
											color: Palette.ourWhite,
											fontSize: 18,
											fontWeight: FontWeight.w600,
										),
									),
									const Spacer(),
									IconButton(
										onPressed: widget.onClose,
										icon: Icon(Icons.close, color: Palette.dampTitles),
										splashRadius: 18,
									),
								],
							),

							const SizedBox(height: 8),

							Text(
								'What’s confusing, missing, or not working how you expected?',
								style: TextStyle(
									color: Palette.dampTitles,
									fontSize: 14,
								),
							),

							const SizedBox(height: 16),

							// Input
							Container(
								decoration: BoxDecoration(
									color: Palette.darkest,
									borderRadius: BorderRadius.circular(12),
								),
								padding: const EdgeInsets.symmetric(horizontal: 12),
								child: TextField(
									controller: _controller,
									maxLines: 5,
									style: TextStyle(color: Palette.ourWhite),
									decoration: InputDecoration(
										border: InputBorder.none,
										hintText: 'Type anything…',
										hintStyle: TextStyle(color: Palette.dampTitles),
									),
								),
							),

							const SizedBox(height: 16),

							// Actions
							Row(
								children: [
									TextButton(
										onPressed: widget.onClose,
										child: Text(
											'Cancel',
											style: TextStyle(color: Palette.dampTitles),
										),
									),
									const Spacer(),
									ElevatedButton(
										onPressed: _submitting ? null : _handleSubmit,
										style: ElevatedButton.styleFrom(
											backgroundColor: Palette.signatureGreen,
											foregroundColor: Colors.black,
											padding: const EdgeInsets.symmetric(
												horizontal: 20,
												vertical: 12,
											),
											shape: RoundedRectangleBorder(
												borderRadius: BorderRadius.circular(12),
											),
										),
										child: _submitting
											? SizedBox(
													width: 16,
													height: 16,
													child: CircularProgressIndicator(
														strokeWidth: 2,
														valueColor: AlwaysStoppedAnimation(Colors.black),
													),
												)
											: const Text(
													'Send',
													style: TextStyle(fontWeight: FontWeight.w600),
												),
									),
								],
							),
						],
					),
				),
			),
		);
	}
}
