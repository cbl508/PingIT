import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pingit/models/device_model.dart';

enum WebhookType { generic, slack, discord, telegram }

class WebhookSettings {
  final String url;
  final WebhookType type;
  final bool enabled;
  final String? botToken; // For Telegram
  final String? chatId;   // For Telegram

  WebhookSettings({
    this.url = '',
    this.type = WebhookType.generic,
    this.enabled = false,
    this.botToken,
    this.chatId,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'type': type.name,
    'enabled': enabled,
    'botToken': botToken,
    'chatId': chatId,
  };

  factory WebhookSettings.fromJson(Map<String, dynamic> json) => WebhookSettings(
    url: json['url'] ?? '',
    type: WebhookType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => WebhookType.generic,
    ),
    enabled: json['enabled'] ?? false,
    botToken: json['botToken'],
    chatId: json['chatId'],
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
    if (oldStatus == newStatus || newStatus == DeviceStatus.unknown) return;

    String? targetUrl;
    Object? payload;

    if (_settings!.type == WebhookType.telegram) {
      if (_settings!.botToken == null || _settings!.chatId == null) return;
      targetUrl = 'https://api.telegram.org/bot${_settings!.botToken}/sendMessage';
      payload = {
        'chat_id': _settings!.chatId,
        'text': _buildTelegramText(device, oldStatus, newStatus),
        'parse_mode': 'HTML',
      };
    } else {
      if (_settings!.url.trim().isEmpty) return;
      targetUrl = _settings!.url;
      payload = _buildPayload(device, oldStatus, newStatus);
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await http.post(
          Uri.parse(targetUrl!),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 10));
        debugPrint('Alert sent to ${_settings!.type.name}');
        return;
      } catch (e) {
        debugPrint('Alert attempt ${attempt + 1}/3 failed: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 2 << attempt));
        }
      }
    }
  }

  String _buildTelegramText(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) {
    final emoji = newStatus == DeviceStatus.offline ? '🔴' : (newStatus == DeviceStatus.degraded ? '🟡' : '🟢');
    final statusStr = newStatus.name.toUpperCase();
    return '<b>$emoji Node Alert: ${device.name}</b>\n'
           'Status: <code>$statusStr</code>\n'
           'Address: <code>${device.address}</code>\n'
           'Type: ${device.checkType.name.toUpperCase()}\n'
           'Time: ${DateFormat('HH:mm:ss').format(DateTime.now())}';
  }

  Map<String, dynamic> _buildPayload(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final isOffline = newStatus == DeviceStatus.offline;
    final isDegraded = newStatus == DeviceStatus.degraded;
    final isRecovery = oldStatus == DeviceStatus.offline && newStatus == DeviceStatus.online;

    switch (_settings!.type) {
      case WebhookType.slack:
        final color = isOffline ? '#EF4444' : (isDegraded ? '#F59E0B' : '#10B981');
        final statusLabel = isRecovery ? 'RECOVERED' : newStatus.name.toUpperCase();
        return {
          'attachments': [
            {
              'color': color,
              'blocks': [
                {
                  'type': 'header',
                  'text': {
                    'type': 'plain_text',
                    'text': 'Node Status Change: ${device.name}',
                    'emoji': true
                  }
                },
                {
                  'type': 'section',
                  'fields': [
                    {'type': 'mrkdwn', 'text': '*Status:*\n$statusLabel'},
                    {'type': 'mrkdwn', 'text': '*Address:*\n`${device.address}`'},
                    {'type': 'mrkdwn', 'text': '*Type:*\n${device.checkType.name.toUpperCase()}'},
                    {'type': 'mrkdwn', 'text': '*Time:*\n$timestamp'}
                  ]
                },
                if (device.lastLatency != null)
                  {
                    'type': 'context',
                    'elements': [
                      {'type': 'mrkdwn', 'text': '*Latency:* ${device.lastLatency!.toStringAsFixed(1)}ms | *Packet Loss:* ${device.packetLoss?.toStringAsFixed(0)}%'}
                    ]
                  }
              ]
            }
          ]
        };

      case WebhookType.discord:
        final color = isOffline ? 0xEF4444 : (isDegraded ? 0xF59E0B : 0x10B981);
        final title = isRecovery
            ? '✅ RECOVERED: ${device.name}'
            : (isOffline ? '❌ OFFLINE: ${device.name}' : '⚠️ DEGRADED: ${device.name}');
        return {
          'embeds': [
            {
              'title': title,
              'color': color,
              'description': 'Infrastructure monitoring alert from **PingIT**.',
              'fields': [
                {'name': 'Address', 'value': '`${device.address}`', 'inline': true},
                {'name': 'Method', 'value': device.checkType.name.toUpperCase(), 'inline': true},
                {'name': 'Previous', 'value': oldStatus.name.toUpperCase(), 'inline': true},
                if (device.lastLatency != null)
                  {'name': 'Telemetry', 'value': '${device.lastLatency!.toStringAsFixed(1)}ms latency', 'inline': false},
              ],
              'footer': {'text': 'PingIT v1.3.2 • Network Oversight'},
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        };

      case WebhookType.telegram:
        // Telegram uses _buildTelegramText instead of this JSON payload
        return {'info': 'telegram_handled_separately'};

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
