import 'package:flutter/material.dart';
import 'package:wishnode/ui/pallet.dart';

class GoalInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final Future<void> Function()? onSubmitted; // called when PLAN GOAL pressed or enter
  final double width; // optional: default matches previous layout

  const GoalInput({
    Key? key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSubmitted,
    this.width = 640,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: width,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Palette.ourWhite,
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(36)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(color: Palette.card, fontSize: 16),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'I want to...',
                        hintStyle: TextStyle(color: Palette.darkest),
                      ),
                      onSubmitted: (_) {
                        if (onSubmitted != null) onSubmitted!();
                      },
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  if (onSubmitted != null) onSubmitted!();
                },
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Palette.signatureGreen,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(36)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: loading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Palette.darkest),
                              ),
                            )
                          : Text('PLAN GOAL',
                              style: TextStyle(color: Palette.darkest, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
