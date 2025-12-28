import 'package:flutter/foundation.dart';

class Log {
  const Log._(); // no instances

  static void d(
    Object? message, {
    String? tag,
  }) {
    if (kReleaseMode) return;

    if (tag != null) {
      // ignore: avoid_print
      print('[$tag] $message');
    } else {
      // ignore: avoid_print
      print(message);
    }
  }

  static void e(
    Object? message, {
    String? tag,
  }) {
    if (kReleaseMode) return;

    if (tag != null) {
      // ignore: avoid_print
      print('[ERROR][$tag] $message');
    } else {
      // ignore: avoid_print
      print('[ERROR] $message');
    }
  }
}
