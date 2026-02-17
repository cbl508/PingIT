import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pingit/models/device_model.dart';

class NotificationService {
  Future<void> init() async {
    // No initialization needed for shell-based notifications
  }

  /// Strips characters that could enable shell injection.
  static String _sanitize(String s) {
    return s.replaceAll(RegExp(r'''['"\\`\${}()\[\];&|<>!#%^]'''), '');
  }

  Future<void> showStatusChangeNotification(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {
    if (oldStatus == DeviceStatus.unknown) return;

    final title = _sanitize(
      '${device.name} is ${newStatus == DeviceStatus.online ? "Online" : newStatus == DeviceStatus.degraded ? "Degraded" : "Offline"}',
    );
    final body = _sanitize(
      newStatus == DeviceStatus.online
          ? '${device.address} is back online. Latency: ${device.lastLatency?.toStringAsFixed(1)} ms'
          : newStatus == DeviceStatus.degraded
              ? '${device.address} is experiencing degraded performance.'
              : '${device.address} has gone offline!',
    );

    if (Platform.isLinux) {
      try {
        // Arguments passed as array — no shell injection possible.
        await Process.run('notify-send', [
          '-a', 'PingIT',
          '-i', newStatus == DeviceStatus.online ? 'network-transmit-receive' : 'network-error',
          title,
          body,
        ]);
      } catch (e) {
        debugPrint('Notification failed (notify-send may not be installed): $e');
      }
    } else if (Platform.isWindows) {
      try {
        await Process.start(
          'powershell',
          [
            '-WindowStyle', 'Hidden',
            '-Command',
            "Add-Type -AssemblyName System.Windows.Forms;"
            "\$n=New-Object System.Windows.Forms.NotifyIcon;"
            "\$n.Icon=[System.Drawing.SystemIcons]::Information;"
            "\$n.Visible=\$true;"
            "\$n.ShowBalloonTip(5000,'$title','$body',"
            "[System.Windows.Forms.ToolTipIcon]::Info);"
            "Start-Sleep 6;\$n.Dispose()",
          ],
          mode: ProcessStartMode.detached,
        );
      } catch (e) {
        debugPrint('Notification failed: $e');
      }
    } else if (Platform.isMacOS) {
      try {
        await Process.run('osascript', [
          '-e', 'display notification "$body" with title "$title"',
        ]);
      } catch (e) {
        debugPrint('Notification failed: $e');
      }
    } else {
      debugPrint('Notification: $title - $body');
    }
  }
}
