import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pingit/models/device_model.dart';

enum WebhookType { generic, slack, discord }

class WebhookSettings {
  final String url;
  final WebhookType type;
  final bool enabled;

  WebhookSettings({
    this.url = '',
    this.type = WebhookType.generic,
    this.enabled = false,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'type': type.name,
    'enabled': enabled,
  };

  factory WebhookSettings.fromJson(Map<String, dynamic> json) => WebhookSettings(
    url: json['url'] ?? '',
    type: WebhookType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => WebhookType.generic,
    ),
    enabled: json['enabled'] ?? false,
  );
}

class QuietHoursSettings {
  final bool enabled;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final List<int> daysOfWeek; // 1=Mon .. 7=Sun (ISO weekday)

  QuietHoursSettings({
    this.enabled = false,
    this.startHour = 22,
    this.startMinute = 0,
    this.endHour = 7,
    this.endMinute = 0,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
  });

  bool isCurrentlyQuiet() {
    if (!enabled) return false;
    final now = DateTime.now();
    if (!daysOfWeek.contains(now.weekday)) return false;

    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;

    if (startMinutes <= endMinutes) {
      // Same-day range: e.g. 09:00 - 17:00
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    } else {
      // Overnight range: e.g. 22:00 - 07:00
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    }
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'startHour': startHour,
    'startMinute': startMinute,
    'endHour': endHour,
    'endMinute': endMinute,
    'daysOfWeek': daysOfWeek,
  };

  factory QuietHoursSettings.fromJson(Map<String, dynamic> json) => QuietHoursSettings(
    enabled: json['enabled'] ?? false,
    startHour: json['startHour'] ?? 22,
    startMinute: json['startMinute'] ?? 0,
    endHour: json['endHour'] ?? 7,
    endMinute: json['endMinute'] ?? 0,
    daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)?.cast<int>() ?? [1, 2, 3, 4, 5, 6, 7],
  );
}

class WebhookService {
  WebhookSettings? _settings;

  void updateSettings(WebhookSettings settings) {
    _settings = settings;
  }

  Future<void> sendAlert(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {
    if (_settings == null || !_settings!.enabled) return;
    if (_settings!.url.trim().isEmpty) return;
    if (oldStatus == newStatus || newStatus == DeviceStatus.unknown) return;

    try {
      final payload = _buildPayload(device, oldStatus, newStatus);
      await http.post(
        Uri.parse(_settings!.url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));
      debugPrint('Webhook sent to ${_settings!.url}');
    } catch (e) {
      debugPrint('Webhook failed: $e');
    }
  }

  Map<String, dynamic> _buildPayload(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final isOffline = newStatus == DeviceStatus.offline;
    final isDegraded = newStatus == DeviceStatus.degraded;
    final isRecovery = oldStatus == DeviceStatus.offline && newStatus == DeviceStatus.online;

    switch (_settings!.type) {
      case WebhookType.slack:
        final color = isOffline ? '#EF4444' : (isDegraded ? '#F59E0B' : '#10B981');
        final emoji = isRecovery
            ? ':white_check_mark:'
            : isOffline
                ? ':red_circle:'
                : (isDegraded ? ':large_yellow_circle:' : ':large_green_circle:');
        final label = isRecovery ? 'RECOVERED' : newStatus.name.toUpperCase();
        return {
          'attachments': [
            {
              'color': color,
              'blocks': [
                {
                  'type': 'section',
                  'text': {
                    'type': 'mrkdwn',
                    'text': '$emoji *${device.name}* is now *$label*\n'
                        '`${device.address}` | ${device.checkType.name.toUpperCase()} | $timestamp',
                  },
                },
              ],
            },
          ],
        };

      case WebhookType.discord:
        final color = isOffline ? 0xEF4444 : (isDegraded ? 0xF59E0B : 0x10B981);
        final title = isRecovery
            ? 'RECOVERED: ${device.name} is back online'
            : '${device.name} is ${newStatus.name.toUpperCase()}';
        return {
          'embeds': [
            {
              'title': title,
              'color': color,
              'fields': [
                {'name': 'Address', 'value': device.address, 'inline': true},
                {'name': 'Check Type', 'value': device.checkType.name.toUpperCase(), 'inline': true},
                {'name': 'Previous Status', 'value': oldStatus.name.toUpperCase(), 'inline': true},
              ],
              'footer': {'text': 'PingIT Monitor'},
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        };

      case WebhookType.generic:
        final eventType = isRecovery ? 'service_recovered' : 'status_change';
        return {
          'event': eventType,
          'device': {
            'name': device.name,
            'address': device.address,
            'type': device.type.name,
            'checkType': device.checkType.name,
          },
          'oldStatus': oldStatus.name,
          'newStatus': newStatus.name,
          'latency': device.lastLatency,
          'packetLoss': device.packetLoss,
          'timestamp': timestamp,
          'source': 'PingIT',
        };
    }
  }
}
