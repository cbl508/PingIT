import 'package:flutter/foundation.dart';
import 'package:pingit/models/device_model.dart';

class AlertService {
  bool isMuted = false;

  Future<void> playAlert(DeviceStatus newStatus) async {
    if (isMuted) return;

    try {
      // Audio playback is currently disabled to ensure cross-platform compatibility
      // without extra native dependencies.
      debugPrint('ALERT: Status changed to $newStatus');
    } catch (e) {
      debugPrint('Error logging alert: $e');
    }
  }
}
