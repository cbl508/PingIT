import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/screens/add_device_screen.dart';
import 'package:pingit/screens/device_details_screen.dart';
import 'package:pingit/screens/device_list_screen.dart';
import 'package:pingit/screens/topology_screen.dart';
import 'package:pingit/screens/logs_screen.dart';
import 'package:pingit/screens/settings_screen.dart';
import 'package:pingit/services/ping_service.dart';
import 'package:pingit/services/storage_service.dart';
import 'package:pingit/services/alert_service.dart';
import 'package:pingit/services/notification_service.dart';
import 'package:pingit/services/email_service.dart';
import 'package:pingit/services/webhook_service.dart';
import 'package:pingit/services/update_service.dart';
import 'package:pingit/services/logging_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final PingService _pingService = PingService();
  final StorageService _storageService = StorageService();
  final AlertService _alertService = AlertService();
  final NotificationService _notificationService = NotificationService();
  final EmailService _emailService = EmailService();
  final WebhookService _webhookService = WebhookService();
  final LoggingService _log = LoggingService();

  List<Device> _devices = [];
  List<DeviceGroup> _groups = [];
  bool _isLoading = true;
  Timer? _timer;
  Timer? _saveDebounceTimer;
  bool _isPolling = false;
  bool _isSaving = false;
  bool _pendingSave = false;
  QuietHoursSettings _quietHours = QuietHoursSettings();

  // Update banner state
  UpdateInfo? _startupUpdateInfo;

  // Status filter from HUD click
  DeviceStatus? _hudStatusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialData();
    _startPolling();
  }

  @override
  void dispose() {
    unawaited(_flushPendingSaves());
    _stopPolling();
    _saveDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      unawaited(_updateDeviceStatuses());
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPolling();
      unawaited(_flushPendingSaves());
    }
  }

  void _startPolling() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      unawaited(_updateDeviceStatuses());
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _loadInitialData() async {
    final devices = await _storageService.loadDevices();
    final groups = await _storageService.loadGroups();
    final emailSettings = await _storageService.loadEmailSettings();
    final webhookSettings = await _storageService.loadWebhookSettings();
    final quietHours = await _storageService.loadQuietHours();
    _emailService.updateSettings(emailSettings);
    _webhookService.updateSettings(webhookSettings);

    // Restore runtime state from persisted history
    for (var device in devices) {
      if (device.history.isNotEmpty) {
        final last = device.history.last;
        device.status = last.status;
        device.lastLatency = last.latencyMs;
        device.packetLoss = last.packetLoss;
        device.lastResponseCode = last.responseCode;
      }
    }

    if (!mounted) return;
    setState(() {
      _devices = devices;
      _groups = groups;
      _quietHours = quietHours;
      _isLoading = false;
    });

    _log.info('PingIT started', data: {'devices': devices.length, 'groups': groups.length});
    _checkForUpdates();
  }

  void _checkForUpdates() async {
    try {
      final update = await UpdateService().checkForUpdate();
      if (update != null && mounted) {
        setState(() => _startupUpdateInfo = update);
      }
    } catch (e) {
      // Silently ignore update check failures on startup
    }
  }

  Future<void> _updateDeviceStatuses() async {
    if (_devices.isEmpty || _isPolling) return;
    _isPolling = true;
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

            // Intelligent Alert Suppression: don't alert if parent is down
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

            // Quiet hours suppression
            if (_quietHours.isCurrentlyQuiet()) {
              shouldSuppress = true;
            }

            if (!shouldSuppress) {
              unawaited(_alertService.playAlert(newS));
              unawaited(
                _notificationService.showStatusChangeNotification(d, oldS, newS),
              );
              unawaited(_emailService.sendAlert(d, oldS, newS));
              unawaited(_webhookService.sendAlert(d, oldS, newS));
            }

            // Critical transitions save immediately
            if (newS == DeviceStatus.offline ||
                (oldS == DeviceStatus.offline && newS == DeviceStatus.online)) {
              hadCriticalTransition = true;
            }
          }
        },
      );

      if (hadCriticalTransition) {
        unawaited(_saveAll());
      } else {
        _scheduleSave();
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _log.error('Failed to update statuses', data: {'error': '$e'});
    } finally {
      _isPolling = false;
    }
  }

  void _scheduleSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 15), () {
      unawaited(_saveAll());
    });
  }

  Future<void> _flushPendingSaves() async {
    _saveDebounceTimer?.cancel();
    await _saveAll();
  }

  Future<void> _saveAll() async {
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

  void _addGroup() {
    final controller = TextEditingController();
    void doCreate() {
      if (controller.text.isNotEmpty) {
        setState(() {
          _groups.add(
            DeviceGroup(
              id: DateTime.now().toString(),
              name: controller.text,
            ),
          );
        });
        unawaited(_saveAll());
        Navigator.pop(context);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'New Infrastructure Group',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g., London Data Center',
          ),
          style: GoogleFonts.inter(),
          onSubmitted: (_) => doCreate(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: doCreate,
            child: const Text('Create Group'),
          ),
        ],
      ),
    );
  }

  void _renameGroup(DeviceGroup group) {
    final controller = TextEditingController(text: group.name);
    void doRename() {
      if (controller.text.isNotEmpty) {
        setState(() {
          group.name = controller.text;
        });
        unawaited(_saveAll());
        Navigator.pop(context);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Rename Group',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group Name'),
          style: GoogleFonts.inter(),
          onSubmitted: (_) => doRename(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: doRename,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteGroup(DeviceGroup group) {
    showDialog(
      context: context,
      builder: (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () {
            setState(() {
              _groups.remove(group);
              for (var device in _devices) {
                if (device.groupId == group.id) {
                  device.groupId = null;
                }
              }
            });
            unawaited(_saveAll());
            Navigator.pop(dialogContext);
          },
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: Text(
              'Delete Group?',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Are you sure you want to delete "${group.name}"? Devices in this group will become unassigned.',
              style: GoogleFonts.inter(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _groups.remove(group);
                    for (var device in _devices) {
                      if (device.groupId == group.id) {
                        device.groupId = null;
                      }
                    }
                  });
                  unawaited(_saveAll());
                  Navigator.pop(dialogContext);
                },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToAddDeviceScreen({Device? existingDevice}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddDeviceScreen(
              device: existingDevice,
              groups: _groups,
              existingDevices: _devices,
            ),
      ),
    );

    if (result == 'delete' && existingDevice != null) {
      setState(() => _devices.remove(existingDevice));
      unawaited(_saveAll());
    } else if (result is Device) {
      setState(() {
        if (existingDevice != null) {
          final index = _devices.indexOf(existingDevice);
          if (index != -1) {
            _devices[index] = result;
          } else {
            _devices.add(result);
          }
        } else {
          _devices.add(result);
        }
      });
      unawaited(_saveAll());
    }
  }

  void _navigateToDetailsScreen(Device device) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DeviceDetailsScreen(
              device: device,
              groups: _groups,
              allDevices: _devices,
            ),
      ),
    );

    if (result == 'delete') {
      setState(() => _devices.remove(device));
      unawaited(_saveAll());
    } else {
      unawaited(_saveAll());
      setState(() {});
    }
  }

  void _handleBulkDelete(Set<String> ids) {
    showDialog(
      context: context,
      builder: (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () {
            setState(() => _devices.removeWhere((d) => ids.contains(d.id)));
            unawaited(_saveAll());
            Navigator.pop(dialogContext);
          },
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: Text('Delete ${ids.length} devices?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            content: Text('This action cannot be undone.', style: GoogleFonts.inter()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  setState(() => _devices.removeWhere((d) => ids.contains(d.id)));
                  unawaited(_saveAll());
                  Navigator.pop(dialogContext);
                },
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBulkMoveToGroup(Set<String> ids) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move to Group', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                for (var d in _devices) {
                  if (ids.contains(d.id)) d.groupId = null;
                }
              });
              unawaited(_saveAll());
              Navigator.pop(context);
            },
            child: const Text('Unassigned'),
          ),
          ..._groups.map((g) => SimpleDialogOption(
            onPressed: () {
              setState(() {
                for (var d in _devices) {
                  if (ids.contains(d.id)) d.groupId = g.id;
                }
              });
              unawaited(_saveAll());
              Navigator.pop(context);
            },
            child: Text(g.name),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _navigateToAddDeviceScreen(),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () => _addGroup(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                labelType: NavigationRailLabelType.selected,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child:
                      Icon(
                            Icons.shield_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28,
                          )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .scaleXY(end: 1.1, duration: 2.seconds),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view),
                    label: Text('Dashboard'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.hub_outlined),
                    selectedIcon: Icon(Icons.hub),
                    label: Text('Topology'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.terminal_outlined),
                    selectedIcon: Icon(Icons.terminal),
                    label: Text('Logs'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.tune_outlined),
                    selectedIcon: Icon(Icons.tune),
                    label: Text('Settings'),
                  ),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: Column(
                  children: [
                    // Update banner — takes layout space, not floating
                    if (_startupUpdateInfo != null)
                      MaterialBanner(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: const Icon(Icons.system_update, color: Color(0xFF3B82F6)),
                        content: Text(
                          'PingIT v${_startupUpdateInfo!.version} is available',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => setState(() {
                              _selectedIndex = 3;
                              _startupUpdateInfo = null;
                            }),
                            child: const Text('VIEW'),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _startupUpdateInfo = null),
                            child: const Text('DISMISS'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          DeviceListScreen(
                            devices: _devices,
                            groups: _groups,
                            isLoading: _isLoading,
                            onUpdate: () => unawaited(_saveAll()),
                            onGroupUpdate: () => unawaited(_saveAll()),
                            onAddDevice: () => _navigateToAddDeviceScreen(),
                            onQuickScan: (addr) => _navigateToAddDeviceScreen(
                              existingDevice: Device(name: 'New Node', address: addr),
                            ),
                            onAddGroup: _addGroup,
                            onRenameGroup: _renameGroup,
                            onDeleteGroup: _deleteGroup,
                            onEditDevice: (d) =>
                                _navigateToAddDeviceScreen(existingDevice: d),
                            onTapDevice: _navigateToDetailsScreen,
                            onBulkDelete: _handleBulkDelete,
                            onBulkMoveToGroup: _handleBulkMoveToGroup,
                            statusFilter: _hudStatusFilter,
                            onStatusFilterChanged: (filter) {
                              setState(() => _hudStatusFilter = filter);
                            },
                          ),
                          TopologyScreen(
                            devices: _devices,
                            onUpdate: () => unawaited(_saveAll()),
                          ),
                          LogsScreen(
                            devices: _devices,
                            groups: _groups,
                            onTapDevice: _navigateToDetailsScreen,
                          ),
                          SettingsScreen(
                            devices: _devices,
                            groups: _groups,
                            onImported: (newDevices) {
                              setState(() {
                                final existingAddresses = _devices
                                    .map((d) => d.address.trim().toLowerCase())
                                    .toSet();
                                final uniqueDevices = newDevices.where(
                                  (d) => existingAddresses.add(d.address.trim().toLowerCase()),
                                );
                                _devices.addAll(uniqueDevices);
                              });
                              unawaited(_saveAll());
                            },
                            onEmailSettingsChanged: (settings) {
                              unawaited(_storageService.saveEmailSettings(settings));
                              _emailService.updateSettings(settings);
                            },
                            onWebhookSettingsChanged: (settings) {
                              unawaited(_storageService.saveWebhookSettings(settings));
                              _webhookService.updateSettings(settings);
                            },
                            onQuietHoursChanged: (settings) {
                              setState(() => _quietHours = settings);
                              unawaited(_storageService.saveQuietHours(settings));
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
