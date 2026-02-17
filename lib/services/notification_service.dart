import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pingit/models/device_model.dart';

class NotificationService {
  Future<void> init() async {
    // No initialization needed for shell-based notifications
  }

  Future<void> showStatusChangeNotification(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {
    if (oldStatus == DeviceStatus.unknown) return;

    final title = '${device.name} is ${newStatus == DeviceStatus.online ? "Online" : newStatus == DeviceStatus.degraded ? "Degraded" : "Offline"}';
    final body = newStatus == DeviceStatus.online
        ? '${device.address} is back online. Latency: ${device.lastLatency?.toStringAsFixed(1)} ms'
        : newStatus == DeviceStatus.degraded
            ? '${device.address} is experiencing degraded performance.'
            : '${device.address} has gone offline!';

    if (Platform.isLinux) {
      try {
        await Process.run('notify-send', [
          '-a', 'PingIT',
          '-i', newStatus == DeviceStatus.online ? 'network-transmit-receive' : 'network-error',
          title,
          body
        ]);
      } catch (e) {
        debugPrint('Notification failed: $e');
      }
    } else if (Platform.isWindows) {
      try {
        final escapedTitle = title.replaceAll("'", "''");
        final escapedBody = body.replaceAll("'", "''");
        await Process.start(
          'powershell',
          [
            '-WindowStyle', 'Hidden',
            '-Command',
            "Add-Type -AssemblyName System.Windows.Forms;"
            "\$n=New-Object System.Windows.Forms.NotifyIcon;"
            "\$n.Icon=[System.Drawing.SystemIcons]::Information;"
            "\$n.Visible=\$true;"
            "\$n.ShowBalloonTip(5000,'$escapedTitle','$escapedBody',"
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
        final escapedTitle = title.replaceAll('"', '\\"');
        final escapedBody = body.replaceAll('"', '\\"');
        await Process.run('osascript', [
          '-e', 'display notification "' + escapedBody + '" with title "' + escapedTitle + '"',
        ]);
      } catch (e) {
        debugPrint('Notification failed: $e');
      }
    } else {
      debugPrint('Notification: $title - $body');
    }
  }
}
