import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // For AppLifecycleState if needed, though usually handled in UI
import 'package:pingit/models/device_model.dart';
import 'package:pingit/services/alert_service.dart';
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
    AlertService? alertService,
    NotificationService? notificationService,
    EmailService? emailService,
    WebhookService? webhookService,
  })  : _pingService = pingService ?? PingService(),
        _storageService = storageService ?? StorageService(),
        _alertService = alertService ?? AlertService(),
        _notificationService = notificationService ?? NotificationService(),
        _emailService = emailService ?? EmailService(),
        _webhookService = webhookService ?? WebhookService() {
    _init();
  }

  Future<void> _init() async {
    await _loadInitialData();
    _startPolling();
  }

  Future<void> _loadInitialData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final devices = await _storageService.loadDevices();
      final groups = await _storageService.loadGroups();
      final emailSettings = await _storageService.loadEmailSettings();
      final webhookSettings = await _storageService.loadWebhookSettings();
      final quietHours = await _storageService.loadQuietHours();
      
      _emailService.updateSettings(emailSettings);
      _webhookService.updateSettings(webhookSettings);

      // Restore runtime state
      for (var device in devices) {
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

      _devices = devices;
      _groups = groups;
      _quietHours = quietHours;
      _log.info('PingIT started', data: {'devices': devices.length, 'groups': groups.length});

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
    notifyListeners(); // Notify that polling started (optional, might cause too many rebuilds if UI listens to isPolling)

    try {
      bool hadCriticalTransition = false;
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

            if (newS == DeviceStatus.offline ||
                (oldS == DeviceStatus.offline && newS == DeviceStatus.online)) {
              hadCriticalTransition = true;
            }
          }
        },
      );

      if (hadCriticalTransition) {
        saveAll(immediate: true);
      } else {
        saveAll(immediate: false);
      }

      notifyListeners();
    } catch (e) {
      _log.error('Failed to update statuses', data: {'error': '$e'});
    } finally {
      _isPolling = false;
      // notifyListeners(); // Maybe don't notify here to avoid double rebuild with the one above if needed
    }
  }

  // --- CRUD Operations ---

  void addDevice(Device device) {
    _devices.add(device);
    saveAll();
    notifyListeners();
  }

  void updateDevice(Device device) {
    final index = _devices.indexWhere((d) => d.id == device.id);
    if (index != -1) {
      _devices[index] = device;
      saveAll();
      notifyListeners();
    }
  }

  void removeDevice(Device device) {
    _devices.remove(device);
    _cleanOrphanedParents();
    saveAll();
    notifyListeners();
  }

  void bulkRemoveDevices(Set<String> ids) {
    _devices.removeWhere((d) => ids.contains(d.id));
    _cleanOrphanedParents();
    saveAll();
    notifyListeners();
  }

  void bulkPauseDevices(Set<String> ids) {
    for (var d in _devices) {
      if (ids.contains(d.id)) d.isPaused = true;
    }
    saveAll();
    notifyListeners();
  }

  void bulkResumeDevices(Set<String> ids) {
    for (var d in _devices) {
      if (ids.contains(d.id)) d.isPaused = false;
    }
    saveAll();
    notifyListeners();
  }

  void bulkMoveDevicesToGroup(Set<String> ids, String? groupId) {
    for (var d in _devices) {
      if (ids.contains(d.id)) d.groupId = groupId;
    }
    saveAll();
    notifyListeners();
  }

  void addGroup(String name) {
    _groups.add(DeviceGroup(id: DateTime.now().toString(), name: name));
    saveAll();
    notifyListeners();
  }

  void updateGroup(DeviceGroup group, String newName) {
    group.name = newName;
    saveAll();
    notifyListeners();
  }

  void removeGroup(DeviceGroup group) {
    _groups.remove(group);
    for (var device in _devices) {
      if (device.groupId == group.id) {
        device.groupId = null;
      }
    }
    saveAll();
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
    _devices.addAll(uniqueDevices);
    saveAll();
    notifyListeners();
  }

  // --- Helper Methods ---

  void _cleanOrphanedParents() {
    final ids = _devices.map((d) => d.id).toSet();
    for (final d in _devices) {
      if (d.parentId != null && !ids.contains(d.parentId)) {
        d.parentId = null;
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
    _saveDebounceTimer = Timer(const Duration(seconds: 15), () {
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
        await _storageService.saveDevices(_devices);
        await _storageService.saveGroups(_groups);
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
