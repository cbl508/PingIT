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

      // Restore runtime state
      for (var device in _devices) {
        if (device.history.isNotEmpty) {
          final last = device.history.last;
          device.status = last.status;
          device.lastLatency = last.latencyMs;
          device.packetLoss = last.packetLoss;
          device.lastResponseCode = last.responseCode;
        }
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
          await _dbService.addHistoryEntry(device.id, history);
          // Prune history periodically or on each entry (prune is fast in SQLite)
          await _dbService.pruneHistory(device.id, device.maxHistory);
        },
      );

      // Save updated device states (status, last latency, etc.)
      for (final d in _devices) {
        await _dbService.saveDevice(d);
      }

      notifyListeners();
    } catch (e) {
      _log.error('Failed to update statuses', data: {'error': '$e'});
    } finally {
      _isPolling = false;
    }
  }

  // --- CRUD Operations ---

  void addDevice(Device device) {
    _devices.add(device);
    _dbService.saveDevice(device);
    notifyListeners();
  }

  void updateDevice(Device device) {
    final index = _devices.indexWhere((d) => d.id == device.id);
    if (index != -1) {
      _devices[index] = device;
      _dbService.saveDevice(device);
      notifyListeners();
    }
  }

  void removeDevice(Device device) {
    _devices.remove(device);
    _cleanOrphanedParents();
    _dbService.deleteDevice(device.id);
    notifyListeners();
  }

  void bulkRemoveDevices(Set<String> ids) {
    for (var id in ids) {
      _devices.removeWhere((d) => d.id == id);
      _dbService.deleteDevice(id);
    }
    _cleanOrphanedParents();
    notifyListeners();
  }

  void bulkPauseDevices(Set<String> ids) {
    for (var d in _devices) {
      if (ids.contains(d.id)) {
        d.isPaused = true;
        _dbService.saveDevice(d);
      }
    }
    notifyListeners();
  }

  void bulkResumeDevices(Set<String> ids) {
    for (var d in _devices) {
      if (ids.contains(d.id)) {
        d.isPaused = false;
        _dbService.saveDevice(d);
      }
    }
    notifyListeners();
  }

  void bulkMoveDevicesToGroup(Set<String> ids, String? groupId) {
    for (var d in _devices) {
      if (ids.contains(d.id)) {
        d.groupId = groupId;
        _dbService.saveDevice(d);
      }
    }
    notifyListeners();
  }

  void addGroup(String name) {
    final g = DeviceGroup(id: DateTime.now().toString(), name: name);
    _groups.add(g);
    _dbService.saveGroup(g);
    notifyListeners();
  }

  void updateGroup(DeviceGroup group, String newName) {
    group.name = newName;
    _dbService.saveGroup(group);
    notifyListeners();
  }

  void removeGroup(DeviceGroup group) {
    _groups.remove(group);
    _dbService.deleteGroup(group.id);
    for (var device in _devices) {
      if (device.groupId == group.id) {
        device.groupId = null;
        _dbService.saveDevice(device);
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
    if (_isSaving) return;

    _isSaving = true;
    try {
      // In SQLite mode, we only need to save the *latest* history entry for devices that updated.
      // But _pingService appends to list.
      // We will iterate devices and save their *latest* history entry if it's not in DB yet?
      // Actually simpler: just save the device record (status/latency) which is cheap.
      // History insert *should* happen in _pingService really, but we'll do it here for now.
      // We'll iterate and check if the last item is newer than what we think? 
      // Or just assume the polling loop added one item.
      
      for (final d in _devices) {
        // Update device status/latency fields
        await _dbService.saveDevice(d); 
        
        // Save the *latest* history item if it exists
        if (d.history.isNotEmpty) {
           // This is slightly inefficient (potential duplicate insert attempt), 
           // but `addHistoryEntry` is just an INSERT.
           // A better way is to have PingService return the new history item and we insert it then.
           // For now, let's rely on the fact that we only really need to persist the *latest* state for the UI,
           // and history accumulation might need a refactor of PingService later.
           
           // CRITICAL: We MUST persist history for the graphs to work on reload.
           // We will take the last item and insert it.
           // Ideally we track which ones are new.
           
           // Let's assume we insert the last one.
           // If we poll every 10s, and save every 5s, we might double insert?
           // No, auto-increment ID on history table handles uniqueness of the ROW, 
           // but we might duplicate the DATA.
           
           // We'll leave history persistence to a specific "onResult" refactor in next step.
           // For now, this just saves device state (Online/Offline) which is the most critical.
           // History might be lost on crash until we fix this in next step.
        }
      }
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
