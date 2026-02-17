import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pingit/models/device_model.dart';

class NotificationService {
  Future<void> init() async {
    // No initialization needed for shell-based notifications
  }

  /// Strips characters that could enable shell injection (for macOS osascript).
  static final RegExp _unsafeCharsRegex = RegExp(r'''['"\\`\${}()\[\];&|<>!#%^]''');
  static String _sanitize(String s) => s.replaceAll(_unsafeCharsRegex, '');

  /// Escapes single quotes for PowerShell single-quoted strings.
  static String _escapePowerShell(String s) => s.replaceAll("'", "''");

  Future<void> showStatusChangeNotification(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {
    if (oldStatus == DeviceStatus.unknown) return;

    final statusLabel = newStatus == DeviceStatus.online
        ? 'Online'
        : newStatus == DeviceStatus.degraded
            ? 'Degraded'
            : 'Offline';
    final rawTitle = '${device.name} is $statusLabel';
    final rawBody = newStatus == DeviceStatus.online
        ? '${device.address} is back online. Latency: ${device.lastLatency?.toStringAsFixed(1)} ms'
        : newStatus == DeviceStatus.degraded
            ? '${device.address} is experiencing degraded performance.'
            : '${device.address} has gone offline!';

    if (Platform.isLinux) {
      try {
        // Arguments passed as array — no shell injection possible.
        await Process.run('notify-send', [
          '-a', 'PingIT',
          '-i', newStatus == DeviceStatus.online ? 'network-transmit-receive' : 'network-error',
          rawTitle,
          rawBody,
        ]);
      } catch (e) {
        debugPrint('Notification failed (notify-send may not be installed): $e');
      }
    } else if (Platform.isWindows) {
      try {
        final title = _escapePowerShell(rawTitle);
        final body = _escapePowerShell(rawBody);
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
        final title = _sanitize(rawTitle);
        final body = _sanitize(rawBody);
        await Process.run('osascript', [
          '-e', 'display notification "$body" with title "$title"',
        ]);
      } catch (e) {
        debugPrint('Notification failed: $e');
      }
    } else {
      debugPrint('Notification: $rawTitle - $rawBody');
    }
  }
}
