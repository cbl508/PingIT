import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LoggingService {
  static final LoggingService _instance = LoggingService._();
  factory LoggingService() => _instance;
  LoggingService._();

  File? _logFile;
  static const int _maxLogSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const int _rotationCount = 3;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}${Platform.pathSeparator}pingit.log');
  }

  Future<void> info(String message, {Map<String, dynamic>? data}) =>
      _write('INFO', message, data: data);

  Future<void> warn(String message, {Map<String, dynamic>? data}) =>
      _write('WARN', message, data: data);

  Future<void> error(String message, {Map<String, dynamic>? data}) =>
      _write('ERROR', message, data: data);

  Future<void> _write(String level, String message, {Map<String, dynamic>? data}) async {
    if (_logFile == null) return;
    try {
      final entry = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'level': level,
        'message': message,
        if (data != null) 'data': data,
      });
      await _logFile!.writeAsString('$entry\n', mode: FileMode.append);
      await _rotateIfNeeded();
    } catch (_) {
      // Logging should never crash the app
    }
  }

  Future<void> _rotateIfNeeded() async {
    if (_logFile == null) return;
    try {
      if (!await _logFile!.exists()) return;
      final size = await _logFile!.length();
      if (size <= _maxLogSizeBytes) return;

      final basePath = _logFile!.path;
      // Delete oldest
      final oldest = File('$basePath.${_rotationCount - 1}');
      if (await oldest.exists()) await oldest.delete();

      // Shift existing rotated files
      for (int i = _rotationCount - 2; i >= 0; i--) {
        final src = File('$basePath.$i');
        if (await src.exists()) {
          await src.rename('$basePath.${i + 1}');
        }
      }

      // Rotate current
      await _logFile!.rename('$basePath.0');
    } catch (_) {
      // Ignore rotation errors
    }
  }
}
