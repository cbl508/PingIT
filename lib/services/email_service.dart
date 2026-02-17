import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:pingit/models/device_model.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class EmailSettings {
  final String smtpServer;
  final int port;
  final String username;
  final String password;
  final String recipientEmail;
  final bool isEnabled;

  EmailSettings({
    this.smtpServer = '',
    this.port = 587,
    this.username = '',
    this.password = '',
    this.recipientEmail = '',
    this.isEnabled = false,
  });

  EmailSettings copyWith({
    String? smtpServer,
    int? port,
    String? username,
    String? password,
    String? recipientEmail,
    bool? isEnabled,
  }) {
    return EmailSettings(
      smtpServer: smtpServer ?? this.smtpServer,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'smtpServer': smtpServer,
    'port': port,
    'username': username,
    'recipientEmail': recipientEmail,
    'isEnabled': isEnabled,
  };

  factory EmailSettings.fromJson(Map<String, dynamic> json) => EmailSettings(
    smtpServer: json['smtpServer'] ?? '',
    port: json['port'] ?? 587,
    username: json['username'] ?? '',
    password: json['password'] ?? '',
    recipientEmail: json['recipientEmail'] ?? '',
    isEnabled: json['isEnabled'] ?? false,
  );
}

class EmailService {
  EmailSettings? _settings;

  void updateSettings(EmailSettings settings) {
    _settings = settings;
  }

  Future<void> sendAlert(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {
    if (_settings == null || !_settings!.isEnabled) return;
    
    // Only alert on transitions between different major statuses
    if (oldStatus == newStatus) return;
    if (newStatus == DeviceStatus.unknown) return;

    if (_settings!.smtpServer.trim().isEmpty ||
        _settings!.username.trim().isEmpty ||
        _settings!.password.trim().isEmpty ||
        _settings!.recipientEmail.trim().isEmpty) {
      debugPrint('Email alert skipped: missing SMTP settings.');
      return;
    }

    final isOffline = newStatus == DeviceStatus.offline;
    final isDegraded = newStatus == DeviceStatus.degraded;
    
    String subject = '';
    String headerTitle = '';
    if (isOffline) {
      subject = 'CRITICAL: ${device.name} is OFFLINE';
      headerTitle = 'Critical Incident';
    } else if (isDegraded) {
      subject = 'WARNING: ${device.name} performance DEGRADED';
      headerTitle = 'Performance Warning';
    } else {
      subject = 'RESOLVED: ${device.name} is BACK ONLINE';
      headerTitle = 'Service Restored';
    }
    
    final statusColor = isOffline ? '#EF4444' : (isDegraded ? '#F59E0B' : '#10B981');
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    
    String downtimeInfo = '';
    if (!isOffline && !isDegraded && device.history.isNotEmpty) {
      // Find when it last went offline to calculate duration
      final lastOfflineIndex = device.history.lastIndexWhere((h) => h.status == DeviceStatus.offline);
      if (lastOfflineIndex != -1) {
        final offlineTime = device.history[lastOfflineIndex].timestamp;
        final duration = DateTime.now().difference(offlineTime);
        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;
        final seconds = duration.inSeconds % 60;
        
        String durationStr = '';
        if (hours > 0) durationStr += '${hours}h ';
        if (minutes > 0) durationStr += '${minutes}m ';
        durationStr += '${seconds}s';
        
        downtimeInfo = '''
          <div style="margin-top: 10px; padding: 12px; background-color: #F1F5F9; border-radius: 8px; border: 1px solid #E2E8F0;">
            <span style="font-weight: bold; color: #475569; font-size: 13px;">Downtime Duration:</span> 
            <span style="color: #1E293B; font-weight: bold;">$durationStr</span>
          </div>
        ''';
      }
    }

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #1E293B; margin: 0; padding: 20px; background-color: #F8FAFC; }
    .container { max-width: 600px; margin: 0 auto; padding: 32px; background-color: #ffffff; border: 1px solid #E2E8F0; border-radius: 16px; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); }
    .header { padding-bottom: 24px; border-bottom: 2px solid #F1F5F9; }
    .status-badge { display: inline-block; padding: 6px 14px; border-radius: 9999px; color: white; font-weight: bold; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
    .content { padding: 32px 0; }
    .footer { font-size: 12px; color: #94A3B8; border-top: 2px solid #F1F5F9; padding-top: 24px; text-align: center; }
    .node-info { background: #F8FAFC; padding: 24px; border-radius: 12px; margin: 24px 0; border: 1px solid #F1F5F9; }
    .label { font-weight: 800; color: #64748B; font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 4px; display: block; }
    .value { font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace; color: #0F172A; font-weight: bold; font-size: 15px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="status-badge" style="background-color: $statusColor;">
        ${newStatus.name}
      </div>
      <h2 style="margin: 16px 0 0 0; color: #0F172A; font-size: 24px; letter-spacing: -0.025em;">$headerTitle</h2>
    </div>
    
    <div class="content">
      <p style="margin-top: 0; font-size: 16px; color: #475569;">
        ${isOffline 
          ? 'An outage has been detected on your monitored infrastructure.' 
          : (isDegraded ? 'Performance thresholds have been exceeded for this node.' : 'The infrastructure node has returned to a healthy state.')}
      </p>
      
      <div class="node-info">
        <div style="margin-bottom: 20px;">
          <span class="label">Node Identity</span>
          <span class="value" style="font-size: 18px; color: #2563EB;">${device.name}</span>
        </div>
        
        <div style="display: table; width: 100%;">
          <div style="display: table-row;">
            <div style="display: table-cell; padding-bottom: 16px;">
              <span class="label">Address</span>
              <span class="value">${device.address}</span>
            </div>
            <div style="display: table-cell; padding-bottom: 16px;">
              <span class="label">Device Role</span>
              <span class="value">${device.type.name.toUpperCase()}</span>
            </div>
          </div>
          <div style="display: table-row;">
            <div style="display: table-cell;">
              <span class="label">Event Timestamp</span>
              <span class="value">$timestamp</span>
            </div>
            <div style="display: table-cell;">
              <span class="label">Check Method</span>
              <span class="value">${device.checkType.name.toUpperCase()}</span>
            </div>
          </div>
        </div>
        
        $downtimeInfo
      </div>
      
      <p style="font-size: 14px; color: #64748B; margin-bottom: 0;">
        ${isOffline 
          ? '<strong>Action Required:</strong> Please verify the network path and service status for this node immediately.' 
          : (isDegraded ? '<strong>Recommendation:</strong> Review the latency and packet loss metrics in the application dashboard.' : '<strong>Verification:</strong> Service recovery has been confirmed via automated telemetry.')}
      </p>
    </div>
    
    <div class="footer">
      Sent by <strong>PingIT Infrastructure Monitor</strong><br/>
      &copy; 2026 PingIT Services. All rights reserved.
    </div>
  </div>
</body>
</html>
''';

    final smtpServer = SmtpServer(
      _settings!.smtpServer,
      port: _settings!.port,
      username: _settings!.username,
      password: _settings!.password,
      ssl: _settings!.port == 465,
      allowInsecure: false,
    );

    final message = Message()
      ..from = Address(_settings!.username, 'PingIT Network Monitor')
      ..recipients.add(_settings!.recipientEmail)
      ..subject = subject
      ..html = htmlContent;

    try {
      await send(message, smtpServer);
      debugPrint('Email alert sent successfully to ${_settings!.recipientEmail}');
    } catch (e) {
      debugPrint('Failed to send email alert: $e');
    }
  }
}
