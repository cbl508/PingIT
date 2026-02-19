import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/services/alert_service.dart';
import 'package:pingit/services/database_service.dart';
import 'package:pingit/services/email_service.dart';
import 'package:pingit/services/logging_service.dart';
import 'package:pingit/services/notification_service.dart';
import 'package:pingit/services/ping_service.dart';
import 'package:pingit/services/storage_service.dart';
import 'package:pingit/services/update_service.dart';
import 'package:pingit/services/webhook_service.dart';

class DeviceProvider extends ChangeNotifier {
  final PingService _pingService;
  final StorageService _storageService;
  final DatabaseService _dbService;
  final AlertService _alertService;
  final NotificationService _notificationService;
  final EmailService _emailService;
  final WebhookService _webhookService;
  final LoggingService _log = LoggingService();

  List<Device> _devices = [];
  List<DeviceGroup> _groups = [];
  bool _isLoading = true;
  bool _isPolling = false;
  bool _isSaving = false;
  bool _pendingSave = false;
  QuietHoursSettings _quietHours = QuietHoursSettings();
  UpdateInfo? _startupUpdateInfo;
  
  // Timer references
  Timer? _timer;
  Timer? _saveDebounceTimer;
  DateTime? _lastPollAttempt;

  // Getters
  List<Device> get devices => _devices;
  List<DeviceGroup> get groups => _groups;
  bool get isLoading => _isLoading;
  bool get isPolling => _isPolling;
  QuietHoursSettings get quietHours => _quietHours;
  UpdateInfo? get startupUpdateInfo => _startupUpdateInfo;

  DeviceProvider({
    PingService? pingService,
    StorageService? storageService,
    DatabaseService? dbService,
    AlertService? alertService,
    NotificationService? notificationService,
    EmailService? emailService,
    WebhookService? webhookService,
  })  : _pingService = pingService ?? PingService(),
        _storageService = storageService ?? StorageService(),
        _dbService = dbService ?? DatabaseService(),
        _alertService = alertService ?? AlertService(),
        _notificationService = notificationService ?? NotificationService(),
        _emailService = emailService ?? EmailService(),
        _webhookService = webhookService ?? WebhookService() {
    _init();
  }

  Future<void> _init() async {
    await _dbService.init();
    await _loadInitialData();
    _startPolling();
  }

  Future<void> _loadInitialData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // settings from secure/shared prefs (keep JSON/Pref storage for these)
      final emailSettings = await _storageService.loadEmailSettings();
      final webhookSettings = await _storageService.loadWebhookSettings();
      final quietHours = await _storageService.loadQuietHours();
      
      _emailService.updateSettings(emailSettings);
      _webhookService.updateSettings(webhookSettings);
      _quietHours = quietHours;

      // Check DB for data
      bool hasDbData = await _dbService.hasData();
      
      if (!hasDbData) {
        // Migration: Load from JSON and save to DB
        _log.info('Migrating data from JSON to SQLite...');
        final legacyDevices = await _storageService.loadDevices();
        final legacyGroups = await _storageService.loadGroups();
        
        for (final g in legacyGroups) await _dbService.saveGroup(g);
        for (final d in legacyDevices) {
          await _dbService.saveDevice(d);
          for (final h in d.history) {
            await _dbService.addHistoryEntry(d.id, h);
          }
        }
        _devices = legacyDevices;
        _groups = legacyGroups;
      } else {
        // Load from DB
        _devices = await _dbService.getAllDevices();
        _groups = await _dbService.getAllGroups();
      }

      // Clear expired maintenance windows (status already restored in getAllDevices)
      for (var device in _devices) {
        if (device.maintenanceUntil != null && DateTime.now().isAfter(device.maintenanceUntil!)) {
          device.maintenanceUntil = null;
        }
      }

      _log.info('PingIT ready', data: {'devices': _devices.length, 'groups': _groups.length});

      // Check for updates
      _checkForUpdates();
    } catch (e) {
      _log.error('Failed to load initial data', data: {'error': '$e'});
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _checkForUpdates() async {
    try {
      final update = await UpdateService().checkForUpdate();
      if (update != null) {
        _startupUpdateInfo = update;
        notifyListeners();
      }
    } catch (e) {
      // Ignore update check failures
    }
  }

  void dismissUpdateBanner() {
    _startupUpdateInfo = null;
    notifyListeners();
  }

  // --- Polling Logic ---

  void startPolling() => _startPolling();

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _startPolling() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDeviceStatuses();
    });
  }

  Future<void> _updateDeviceStatuses() async {
    if (_devices.isEmpty || _isPolling) return;

    final backoff = _pingService.backoffSeconds;
    if (backoff > 0 && _lastPollAttempt != null) {
      final elapsed = DateTime.now().difference(_lastPollAttempt!).inSeconds;
      if (elapsed < backoff) return;
    }

    _isPolling = true;
    _lastPollAttempt = DateTime.now();
    notifyListeners(); 

    try {
      final checkedDevices = <Device>{};

      await _pingService.pingAllDevices(
        _devices,
        onStatusChanged: (d, oldS, newS) {
          if (oldS != DeviceStatus.unknown && oldS != newS) {
            _log.info('Status change: ${d.name}', data: {
              'address': d.address,
              'from': oldS.name,
              'to': newS.name,
            });

            bool shouldSuppress = false;
            if (d.parentId != null && newS == DeviceStatus.offline) {
              final parent = _devices.cast<Device?>().firstWhere(
                (node) => node?.id == d.parentId,
                orElse: () => null,
              );
              if (parent != null && parent.status == DeviceStatus.offline) {
                shouldSuppress = true;
              }
            }

            if (d.isInMaintenance) shouldSuppress = true;
            if (_quietHours.isCurrentlyQuiet()) shouldSuppress = true;

            if (!shouldSuppress) {
              _alertService.playAlert(newS);
              _notificationService.showStatusChangeNotification(d, oldS, newS);
              _emailService.sendAlert(d, oldS, newS);
              _webhookService.sendAlert(d, oldS, newS);
            } else {
              final reason = d.isInMaintenance
                  ? 'maintenance window'
                  : _quietHours.isCurrentlyQuiet()
                      ? 'quiet hours'
                      : 'parent offline';
              _log.info('Alert suppressed: ${d.name}', data: {'reason': reason});
            }
          }
        },
        onResult: (device, history) async {
          checkedDevices.add(device);
          await _dbService.addHistoryEntry(device.id, history);
          await _dbService.pruneHistory(device.id, device.maxHistory);
        },
      );

      // Only save devices that were actually checked in this cycle
      for (final d in checkedDevices) {
        await _dbService.saveDevice(d);
      }

      notifyListeners();
    } catch (e) {
      _log.error('Failed to update statuses', data: {'error': '$e'});
    } finally {
      _isPolling = false;
      notifyListeners();
    }
  }

  // --- CRUD Operations ---

  /// Wraps a DB future with error logging to prevent silent failures.
  void _persist(Future<void> Function() operation, String description) {
    operation().catchError((e) {
      _log.error('DB write failed: $description', data: {'error': '$e'});
    });
  }

  void addDevice(Device device) {
    _devices.add(device);
    _persist(() => _dbService.saveDevice(device), 'addDevice(${device.name})');
    notifyListeners();
  }

  void updateDevice(Device device) {
    final index = _devices.indexWhere((d) => d.id == device.id);
    if (index != -1) {
      _devices[index] = device;
      _persist(() => _dbService.saveDevice(device), 'updateDevice(${device.name})');
      notifyListeners();
    }
  }

  void removeDevice(Device device) {
    _devices.remove(device);
    _cleanOrphanedParents();
    _persist(() => _dbService.deleteDevice(device.id), 'removeDevice(${device.name})');
    notifyListeners();
  }

  void bulkRemoveDevices(Set<String> ids) {
    for (var id in ids) {
      _devices.removeWhere((d) => d.id == id);
      _persist(() => _dbService.deleteDevice(id), 'bulkRemoveDevice($id)');
    }
    _cleanOrphanedParents();
    notifyListeners();
  }

  void bulkPauseDevices(Set<String> ids) {
    for (var d in _devices) {
      if (ids.contains(d.id)) {
        d.isPaused = true;
        _persist(() => _dbService.saveDevice(d), 'bulkPause(${d.name})');
      }
    }
    notifyListeners();
  }

  void bulkResumeDevices(Set<String> ids) {
    for (var d in _devices) {
      if (ids.contains(d.id)) {
        d.isPaused = false;
        _persist(() => _dbService.saveDevice(d), 'bulkResume(${d.name})');
      }
    }
    notifyListeners();
  }

  void bulkMoveDevicesToGroup(Set<String> ids, String? groupId) {
    for (var d in _devices) {
      if (ids.contains(d.id)) {
        d.groupId = groupId;
        _persist(() => _dbService.saveDevice(d), 'bulkMove(${d.name})');
      }
    }
    notifyListeners();
  }

  void addGroup(String name) {
    final g = DeviceGroup(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name);
    _groups.add(g);
    _persist(() => _dbService.saveGroup(g), 'addGroup($name)');
    notifyListeners();
  }

  void updateGroup(DeviceGroup group, String newName) {
    group.name = newName;
    _persist(() => _dbService.saveGroup(group), 'updateGroup($newName)');
    notifyListeners();
  }

  void removeGroup(DeviceGroup group) {
    _groups.remove(group);
    _persist(() => _dbService.deleteGroup(group.id), 'removeGroup(${group.name})');
    for (var device in _devices) {
      if (device.groupId == group.id) {
        device.groupId = null;
        _persist(() => _dbService.saveDevice(device), 'unassignDevice(${device.name})');
      }
    }
    notifyListeners();
  }

  void updateQuietHours(QuietHoursSettings settings) {
    _quietHours = settings;
    _storageService.saveQuietHours(settings);
    notifyListeners();
  }
  
  void updateEmailSettings(EmailSettings settings) {
    _storageService.saveEmailSettings(settings);
    _emailService.updateSettings(settings);
  }

  void updateWebhookSettings(WebhookSettings settings) {
    _storageService.saveWebhookSettings(settings);
    _webhookService.updateSettings(settings);
  }

  void importDevices(List<Device> newDevices) {
    final existingAddresses = _devices
        .map((d) => d.address.trim().toLowerCase())
        .toSet();
    final uniqueDevices = newDevices.where(
      (d) => existingAddresses.add(d.address.trim().toLowerCase()),
    );
    for (var d in uniqueDevices) {
      _devices.add(d);
      _dbService.saveDevice(d);
    }
    notifyListeners();
  }

  // --- Helper Methods ---

  void _cleanOrphanedParents() {
    final ids = _devices.map((d) => d.id).toSet();
    for (final d in _devices) {
      if (d.parentId != null && !ids.contains(d.parentId)) {
        d.parentId = null;
        _dbService.saveDevice(d);
      }
    }
  }

  // --- Persistence ---

  void saveAll({bool immediate = false}) {
    if (immediate) {
      _flushPendingSaves();
    } else {
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 5), () {
      _flushPendingSaves();
    });
  }

  Future<void> _flushPendingSaves() async {
    _saveDebounceTimer?.cancel();
    if (_isSaving) {
      _pendingSave = true;
      return;
    }

    _isSaving = true;
    try {
      do {
        _pendingSave = false;
        for (final d in _devices) {
          await _dbService.saveDevice(d);
        }
      } while (_pendingSave);
    } catch (e) {
      _log.error('Failed to persist data', data: {'error': '$e'});
    } finally {
      _isSaving = false;
    }
  }

  @override
  void dispose() {
    _flushPendingSaves();
    stopPolling();
    _saveDebounceTimer?.cancel();
    super.dispose();
  }
}
