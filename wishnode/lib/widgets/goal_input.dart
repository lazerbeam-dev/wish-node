import 'package:flutter/material.dart';

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
                    color: Color(0xFFD6D8E1),
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(36)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(color: Color(0xFF282A2F), fontSize: 16),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'I want to...',
                        hintStyle: TextStyle(color: Color(0xFF545B75)),
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
                    color: Color(0xFF545B75),
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
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text('PLAN GOAL',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
