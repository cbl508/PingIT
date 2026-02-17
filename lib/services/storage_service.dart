import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/services/email_service.dart';

class StorageService {
  static const String _emailPasswordKey = 'pingit_email_password';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  // Devices Storage
  Future<File> get _devicesFile async {
    final path = await _localPath;
    return File('$path/devices.json');
  }

  // Groups Storage
  Future<File> get _groupsFile async {
    final path = await _localPath;
    return File('$path/groups.json');
  }

  // Email Settings Storage
  Future<File> get _emailSettingsFile async {
    final path = await _localPath;
    return File('$path/email_settings.json');
  }

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
    final file = await _devicesFile;
    final List<Map<String, dynamic>> json = devices.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(json));
  }

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
    final file = await _groupsFile;
    final List<Map<String, dynamic>> json = groups.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(json));
  }

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

      // Migration path: if password existed in legacy JSON, move it to secure storage.
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
}
