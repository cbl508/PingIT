import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pingit/models/device_model.dart';

class AlertService {
  bool isMuted = false;

  Future<void> playAlert(DeviceStatus newStatus) async {
    if (isMuted) return;
    try {
      if (Platform.isLinux) {
        await _playLinux(newStatus);
      } else if (Platform.isMacOS) {
        await _playMacOS(newStatus);
      } else if (Platform.isWindows) {
        await _playWindows(newStatus);
      } else {
        debugPrint('ALERT: Status changed to $newStatus');
      }
    } catch (e) {
      debugPrint('Alert sound failed: $e');
    }
  }

  Future<void> _playLinux(DeviceStatus status) async {
    final soundFile = status == DeviceStatus.offline
        ? '/usr/share/sounds/freedesktop/stereo/dialog-error.oga'
        : '/usr/share/sounds/freedesktop/stereo/dialog-information.oga';
    try {
      final result = await Process.run('paplay', [soundFile]);
      if (result.exitCode != 0) {
        await Process.run('aplay', [soundFile.replaceAll('.oga', '.wav')]);
      }
    } catch (_) {
      debugPrint('ALERT (no audio player): Status -> $status');
    }
  }

  Future<void> _playMacOS(DeviceStatus status) async {
    final soundFile = status == DeviceStatus.offline
        ? '/System/Library/Sounds/Sosumi.aiff'
        : '/System/Library/Sounds/Glass.aiff';
    await Process.run('afplay', [soundFile]);
  }

  Future<void> _playWindows(DeviceStatus status) async {
    final soundMethod = status == DeviceStatus.offline ? 'Exclamation' : 'Asterisk';
    await Process.start(
      'powershell',
      ['-WindowStyle', 'Hidden', '-Command', '[System.Media.SystemSounds]::$soundMethod.Play()'],
      mode: ProcessStartMode.detached,
    );
  }
}
