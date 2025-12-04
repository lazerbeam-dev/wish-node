// wizard_toast.dart
import 'dart:math';
import 'package:flutter/material.dart';
void showWizardToast(BuildContext ctx, String wishTitle, {String? forced}) {
  final lines = [
    'Nice — one more rune etched.',
    'Good. The genie is impressed (slightly).',
    'The light grows brighter. Keep going.',
  ];
  final text = forced ?? lines[Random().nextInt(lines.length)];
  final morsel = '$text — $wishTitle';
  final snack = SnackBar(content: Text(morsel), duration: Duration(seconds:2));
  ScaffoldMessenger.of(ctx).showSnackBar(snack);
}