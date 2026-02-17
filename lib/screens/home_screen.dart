import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:pingit/services/update_service.dart';

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

  List<Device> _devices = [];
  List<DeviceGroup> _groups = [];
  bool _isLoading = true;
  Timer? _timer;
  Timer? _saveDebounceTimer;
  bool _isPolling = false;
  bool _isSaving = false;
  bool _pendingSave = false;

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
    _emailService.updateSettings(emailSettings);

    if (!mounted) return;
    setState(() {
      _devices = devices;
      _groups = groups;
      _isLoading = false;
    });

    // Check for updates in background
    _checkForUpdates();
  }

  void _checkForUpdates() async {
    try {
      final update = await UpdateService().checkForUpdate();
      if (update != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PingIT v${update.version} is available'),
            action: SnackBarAction(
              label: 'VIEW',
              onPressed: () => setState(() => _selectedIndex = 3),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      // Silently ignore update check failures on startup
    }
  }

  Future<void> _updateDeviceStatuses() async {
    if (_devices.isEmpty || _isPolling) return;
    _isPolling = true;
    try {
      await _pingService.pingAllDevices(
        _devices,
        onStatusChanged: (d, oldS, newS) {
          if (oldS != DeviceStatus.unknown && oldS != newS) {
            // Intelligent Alert Suppression: don't alert if parent is down
            bool shouldSuppress = false;
            if (d.parentId != null && newS == DeviceStatus.offline) {
              final parent = _devices.cast<Device?>().firstWhere(
                (node) => node?.id == d.parentId,
                orElse: () => null,
              );
              if (parent != null && parent.status == DeviceStatus.offline) {
                shouldSuppress = true;
                debugPrint('Alert suppressed for ${d.name} because parent ${parent.name} is offline.');
              }
            }

            if (!shouldSuppress) {
              unawaited(_alertService.playAlert(newS));
              unawaited(
                _notificationService.showStatusChangeNotification(d, oldS, newS),
              );
              unawaited(_emailService.sendAlert(d, oldS, newS));
            }
          }
        },
      );
      _scheduleSave();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Failed to update statuses: $e');
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
      debugPrint('Failed to persist data: $e');
    } finally {
      _isSaving = false;
    }
  }

  void _addGroup() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'New Infrastructure Group',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'e.g., London Data Center',
          ),
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
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
            },
            child: const Text('Create Group'),
          ),
        ],
      ),
    );
  }

  void _renameGroup(DeviceGroup group) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Rename Group',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Group Name'),
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  group.name = controller.text;
                });
                unawaited(_saveAll());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteGroup(DeviceGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
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
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _navigateToAddDeviceScreen({Device? existingDevice}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddDeviceScreen(device: existingDevice, groups: _groups),
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
            // Device was not in list (e.g. created via Quick Scan)
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
            DeviceDetailsScreen(device: device, groups: _groups),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
