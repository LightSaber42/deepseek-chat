import 'package:flutter/foundation.dart';

class LogUtils {
  static final DateTime _startTime = DateTime.now();

  static void log(String message) {
    final elapsed = DateTime.now().difference(_startTime).inMilliseconds / 1000.0;
    debugPrint('[${elapsed.toStringAsFixed(3)}s] $message');
  }
}