import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/services/email_service.dart';
import 'package:pingit/services/webhook_service.dart';

class StorageService {
  static const String _emailPasswordKey = 'pingit_email_password';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _devicesFile async {
    final path = await _localPath;
    return File('$path/devices.json');
  }

  Future<File> get _groupsFile async {
    final path = await _localPath;
    return File('$path/groups.json');
  }

  Future<File> get _emailSettingsFile async {
    final path = await _localPath;
    return File('$path/email_settings.json');
  }

  Future<File> get _webhookSettingsFile async {
    final path = await _localPath;
    return File('$path/webhook_settings.json');
  }

  Future<File> get _quietHoursFile async {
    final path = await _localPath;
    return File('$path/quiet_hours.json');
  }

  // Devices
  Future<List<Device>> loadDevices() async {
    try {
      final file = await _devicesFile;
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      final List<dynamic> json = jsonDecode(contents);
      return json.map((e) => Device.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Failed to load devices: $e');
      return [];
    }
  }

  Future<void> saveDevices(List<Device> devices) async {
    // Snapshot JSON synchronously before any async gap to avoid race conditions
    final snapshot = jsonEncode(devices.map((e) => e.toJson()).toList());
    final file = await _devicesFile;
    await file.writeAsString(snapshot);
  }

  // Groups
  Future<List<DeviceGroup>> loadGroups() async {
    try {
      final file = await _groupsFile;
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      final List<dynamic> json = jsonDecode(contents);
      return json.map((e) => DeviceGroup.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Failed to load groups: $e');
      return [];
    }
  }

  Future<void> saveGroups(List<DeviceGroup> groups) async {
    // Snapshot JSON synchronously before any async gap to avoid race conditions
    final snapshot = jsonEncode(groups.map((e) => e.toJson()).toList());
    final file = await _groupsFile;
    await file.writeAsString(snapshot);
  }

  // Email Settings
  Future<EmailSettings> loadEmailSettings() async {
    try {
      final file = await _emailSettingsFile;
      final securePassword = await _secureStorage.read(key: _emailPasswordKey) ?? '';
      if (!await file.exists()) {
        return EmailSettings(password: securePassword);
      }

      final contents = await file.readAsString();
      final fromFile = EmailSettings.fromJson(jsonDecode(contents));

      if (securePassword.isNotEmpty) {
        return fromFile.copyWith(password: securePassword);
      }

      if (fromFile.password.isNotEmpty) {
        await _secureStorage.write(key: _emailPasswordKey, value: fromFile.password);
        await file.writeAsString(jsonEncode(fromFile.copyWith(password: '').toJson()));
      }

      return fromFile;
    } catch (e) {
      debugPrint('Failed to load email settings: $e');
      return EmailSettings();
    }
  }

  Future<void> saveEmailSettings(EmailSettings settings) async {
    final file = await _emailSettingsFile;
    await file.writeAsString(jsonEncode(settings.toJson()));
    await _secureStorage.write(key: _emailPasswordKey, value: settings.password);
  }

  // Webhook Settings
  Future<WebhookSettings> loadWebhookSettings() async {
    try {
      final file = await _webhookSettingsFile;
      if (!await file.exists()) return WebhookSettings();
      final contents = await file.readAsString();
      return WebhookSettings.fromJson(jsonDecode(contents));
    } catch (e) {
      debugPrint('Failed to load webhook settings: $e');
      return WebhookSettings();
    }
  }

  Future<void> saveWebhookSettings(WebhookSettings settings) async {
    final file = await _webhookSettingsFile;
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  // Quiet Hours
  Future<QuietHoursSettings> loadQuietHours() async {
    try {
      final file = await _quietHoursFile;
      if (!await file.exists()) return QuietHoursSettings();
      final contents = await file.readAsString();
      return QuietHoursSettings.fromJson(jsonDecode(contents));
    } catch (e) {
      debugPrint('Failed to load quiet hours: $e');
      return QuietHoursSettings();
    }
  }

  Future<void> saveQuietHours(QuietHoursSettings settings) async {
    final file = await _quietHoursFile;
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}
