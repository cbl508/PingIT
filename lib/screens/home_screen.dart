import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/providers/device_provider.dart';
import 'package:pingit/screens/dashboard_screen.dart';
import 'package:pingit/screens/add_device_screen.dart';
import 'package:pingit/screens/device_details_screen.dart';
import 'package:pingit/screens/device_list_screen.dart';
import 'package:pingit/screens/topology_screen.dart';
import 'package:pingit/screens/logs_screen.dart';
import 'package:pingit/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  
  // Status filter from HUD click
  DeviceStatus? _hudStatusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<DeviceProvider>();
    if (state == AppLifecycleState.resumed) {
      provider.startPolling();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      provider.stopPolling();
      // provider.saveAll(immediate: true); // DB handles persistence now
    }
  }

  void _navigateToAddDeviceScreen(BuildContext context, {Device? existingDevice}) async {
    final provider = context.read<DeviceProvider>();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddDeviceScreen(
          device: existingDevice,
          groups: provider.groups,
          existingDevices: provider.devices,
        ),
      ),
    );

    if (result == 'delete' && existingDevice != null) {
      provider.removeDevice(existingDevice);
    } else if (result is Device) {
      if (existingDevice != null) {
        provider.updateDevice(result);
      } else {
        provider.addDevice(result);
      }
    }
  }

  void _navigateToDetailsScreen(BuildContext context, Device device) async {
    final provider = context.read<DeviceProvider>();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceDetailsScreen(
          device: device,
          groups: provider.groups,
          allDevices: provider.devices,
        ),
      ),
    );

    if (result == 'delete') {
      provider.removeDevice(device);
    } else if (result is Device && result.id != device.id) {
      // Clone result — add as new device
      provider.addDevice(result);
    } else {
      // provider.saveAll(); // DB handles persistence now
      provider.updateDevice(device); 
    }
  }

  void _addGroup(BuildContext context) {
    final controller = TextEditingController();
    void doCreate() {
      if (controller.text.isNotEmpty) {
        context.read<DeviceProvider>().addGroup(controller.text);
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

  void _renameGroup(BuildContext context, DeviceGroup group) {
    final controller = TextEditingController(text: group.name);
    void doRename() {
      if (controller.text.isNotEmpty) {
        context.read<DeviceProvider>().updateGroup(group, controller.text);
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

  void _deleteGroup(BuildContext context, DeviceGroup group) {
    showDialog(
      context: context,
      builder: (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () {
            context.read<DeviceProvider>().removeGroup(group);
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
                  context.read<DeviceProvider>().removeGroup(group);
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _navigateToAddDeviceScreen(context),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () => _addGroup(context),
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
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Dashboard'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view),
                    label: Text('Infrastructure'),
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
                    if (provider.startupUpdateInfo != null)
                      MaterialBanner(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: const Icon(Icons.system_update, color: Color(0xFF3B82F6)),
                        content: Text(
                          'PingIT v${provider.startupUpdateInfo!.version} is available',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                               setState(() => _selectedIndex = 4); // Settings is now index 4
                               provider.dismissUpdateBanner();
                            },
                            child: const Text('VIEW'),
                          ),
                          TextButton(
                            onPressed: () => provider.dismissUpdateBanner(),
                            child: const Text('DISMISS'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          const DashboardScreen(),
                          DeviceListScreen(
                            devices: provider.devices,
                            groups: provider.groups,
                            isLoading: provider.isLoading,
                            onAddDevice: () => _navigateToAddDeviceScreen(context),
                            onQuickScan: (addr) => _navigateToAddDeviceScreen(
                              context,
                              existingDevice: Device(name: 'New Node', address: addr),
                            ),
                            onAddGroup: () => _addGroup(context),
                            onRenameGroup: (g) => _renameGroup(context, g),
                            onDeleteGroup: (g) => _deleteGroup(context, g),
                            onEditDevice: (d) =>
                                _navigateToAddDeviceScreen(context, existingDevice: d),
                            onTapDevice: (d) => _navigateToDetailsScreen(context, d),
                            statusFilter: _hudStatusFilter,
                            onStatusFilterChanged: (filter) {
                              setState(() => _hudStatusFilter = filter);
                            },
                          ),
                          const TopologyScreen(),
                          LogsScreen(
                            devices: provider.devices,
                            groups: provider.groups,
                            onTapDevice: (d) => _navigateToDetailsScreen(context, d),
                          ),
                          SettingsScreen(
                            devices: provider.devices,
                            groups: provider.groups,
                            onImported: (newDevices) => provider.importDevices(newDevices),
                            onEmailSettingsChanged: (settings) => provider.updateEmailSettings(settings),
                            onWebhookSettingsChanged: (settings) => provider.updateWebhookSettings(settings),
                            onQuietHoursChanged: (settings) => provider.updateQuietHours(settings),
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
