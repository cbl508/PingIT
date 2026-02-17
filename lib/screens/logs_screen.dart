import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pingit/models/device_model.dart';

enum _FontSize { small, medium, large }

class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    required this.devices,
    required this.groups,
    required this.onTapDevice,
  });
  final List<Device> devices;
  final List<DeviceGroup> groups;
  final Function(Device) onTapDevice;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  int _filterIndex = 0; // 0=All, 1=Online, 2=Degraded, 3=Offline, 4=Paused
  String _searchQuery = '';
  _FontSize _fontSize = _FontSize.medium;

  double get _nameFontSize {
    switch (_fontSize) {
      case _FontSize.small: return 13;
      case _FontSize.medium: return 14;
      case _FontSize.large: return 15;
    }
  }

  double get _timestampFontSize {
    switch (_fontSize) {
      case _FontSize.small: return 10;
      case _FontSize.medium: return 12;
      case _FontSize.large: return 13;
    }
  }

  double get _addressFontSize {
    switch (_fontSize) {
      case _FontSize.small: return 11;
      case _FontSize.medium: return 13;
      case _FontSize.large: return 14;
    }
  }

  List<({Device device, StatusHistory log})> _getFilteredLogs() {
    var allLogs = widget.devices
        .expand((d) => d.history.map((h) => (device: d, log: h)))
        .toList();

    switch (_filterIndex) {
      case 1:
        allLogs = allLogs.where((item) => item.log.status == DeviceStatus.online).toList();
        break;
      case 2:
        allLogs = allLogs.where((item) => item.log.status == DeviceStatus.degraded).toList();
        break;
      case 3:
        allLogs = allLogs.where((item) => item.log.status == DeviceStatus.offline).toList();
        break;
      case 4:
        final pausedIds = widget.devices.where((d) => d.isPaused).map((d) => d.id).toSet();
        allLogs = allLogs.where((item) => pausedIds.contains(item.device.id)).toList();
        break;
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      allLogs = allLogs.where((item) =>
          item.device.name.toLowerCase().contains(q) ||
          item.device.address.toLowerCase().contains(q)).toList();
    }

    allLogs.sort((a, b) => b.log.timestamp.compareTo(a.log.timestamp));
    return allLogs;
  }

  Future<void> _exportCsv() async {
    final logs = _getFilteredLogs();
    if (logs.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('Device,Address,Timestamp,Status,Latency (ms),Packet Loss (%),Response Code');
    for (final item in logs) {
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(item.log.timestamp);
      final latency = item.log.latencyMs?.toStringAsFixed(1) ?? '';
      final loss = item.log.packetLoss?.toStringAsFixed(1) ?? '';
      final code = item.log.responseCode?.toString() ?? '';
      // Escape commas in device name
      final name = item.device.name.contains(',') ? '"${item.device.name}"' : item.device.name;
      buffer.writeln('$name,${item.device.address},$ts,${item.log.status.name},$latency,$loss,$code');
    }

    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Event Logs',
        fileName: 'pingit_logs_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result != null) {
        await File(result).writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported ${logs.length} events to CSV')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allLogs = _getFilteredLogs();
    final surfaceColor = Theme.of(context).colorScheme.onSurface;
    final subtleColor = Theme.of(context).colorScheme.onSurfaceVariant;

    // Counts for filter badges
    final totalCount = widget.devices.expand((d) => d.history).length;
    final onlineCount = widget.devices.expand((d) => d.history).where((h) => h.status == DeviceStatus.online).length;
    final degradedCount = widget.devices.expand((d) => d.history).where((h) => h.status == DeviceStatus.degraded).length;
    final offlineCount = widget.devices.expand((d) => d.history).where((h) => h.status == DeviceStatus.offline).length;
    final pausedDeviceCount = widget.devices.where((d) => d.isPaused).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Event Stream',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options',
            onSelected: (val) {
              if (val == 'export') {
                _exportCsv();
              } else if (val == 'small') {
                setState(() => _fontSize = _FontSize.small);
              } else if (val == 'medium') {
                setState(() => _fontSize = _FontSize.medium);
              } else if (val == 'large') {
                setState(() => _fontSize = _FontSize.large);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'export', child: Row(children: [
                Icon(Icons.download_outlined, size: 18), SizedBox(width: 12), Text('Export CSV'),
              ])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'small', child: Row(children: [
                Icon(Icons.text_fields, size: 18, color: _fontSize == _FontSize.small ? Theme.of(context).colorScheme.primary : null),
                const SizedBox(width: 12),
                Text('Small Text', style: TextStyle(fontWeight: _fontSize == _FontSize.small ? FontWeight.bold : FontWeight.normal)),
              ])),
              PopupMenuItem(value: 'medium', child: Row(children: [
                Icon(Icons.text_fields, size: 18, color: _fontSize == _FontSize.medium ? Theme.of(context).colorScheme.primary : null),
                const SizedBox(width: 12),
                Text('Medium Text', style: TextStyle(fontWeight: _fontSize == _FontSize.medium ? FontWeight.bold : FontWeight.normal)),
              ])),
              PopupMenuItem(value: 'large', child: Row(children: [
                Icon(Icons.text_fields, size: 18, color: _fontSize == _FontSize.large ? Theme.of(context).colorScheme.primary : null),
                const SizedBox(width: 12),
                Text('Large Text', style: TextStyle(fontWeight: _fontSize == _FontSize.large ? FontWeight.bold : FontWeight.normal)),
              ])),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search logs by node name or address...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(0, 'All', totalCount, Icons.history, const Color(0xFF64748B)),
                    _buildFilterChip(1, 'Online', onlineCount, Icons.check_circle_outline, Colors.green),
                    _buildFilterChip(2, 'Degraded', degradedCount, Icons.warning_amber_rounded, Colors.orange),
                    _buildFilterChip(3, 'Offline', offlineCount, Icons.error_outline, Colors.red),
                    _buildFilterChip(4, 'Paused', pausedDeviceCount, Icons.pause_circle_outline, Colors.blueGrey),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: allLogs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).disabledColor),
                  const SizedBox(height: 12),
                  Text('No events match this filter',
                      style: GoogleFonts.inter(color: Theme.of(context).disabledColor)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: allLogs.length.clamp(0, 1000),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemBuilder: (context, index) {
                final item = allLogs[index];
                final statusColor = _statusColor(item.log.status);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.1)),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_statusIcon(item.log.status), color: statusColor, size: 18),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.device.name,
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: _nameFontSize, color: surfaceColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('HH:mm:ss \u2022 MMM dd').format(item.log.timestamp),
                          style: GoogleFonts.jetBrainsMono(fontSize: _timestampFontSize, color: subtleColor),
                        ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Icon(item.device.typeIcon, size: 12, color: subtleColor),
                        const SizedBox(width: 4),
                        Text(
                          item.device.address,
                          style: GoogleFonts.jetBrainsMono(fontSize: _addressFontSize, color: subtleColor),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _statusLabel(item.log),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: _addressFontSize,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 18, color: subtleColor),
                      onSelected: (val) {
                        if (val == 'navigate') widget.onTapDevice(item.device);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'navigate',
                          child: Row(
                            children: [
                              Icon(Icons.analytics_outlined, size: 18),
                              SizedBox(width: 12),
                              Text('View Node Details'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildFilterChip(int index, String label, int count, IconData icon, Color? color) {
    final isSelected = _filterIndex == index;
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : effectiveColor),
      label: Text(
        '$label ($count)',
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : null,
        ),
      ),
      selectedColor: effectiveColor,
      onSelected: (_) => setState(() => _filterIndex = index),
    );
  }

  Color _statusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online: return Colors.green;
      case DeviceStatus.degraded: return Colors.orange;
      case DeviceStatus.offline: return Colors.red;
      default: return Colors.blueGrey;
    }
  }

  IconData _statusIcon(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online: return Icons.check_circle_outline;
      case DeviceStatus.degraded: return Icons.warning_amber_rounded;
      case DeviceStatus.offline: return Icons.error_outline;
      default: return Icons.pause_circle_outline;
    }
  }

  String _statusLabel(StatusHistory log) {
    switch (log.status) {
      case DeviceStatus.online: return '${log.latencyMs?.toStringAsFixed(1)}ms';
      case DeviceStatus.degraded: return '${log.latencyMs?.toStringAsFixed(1)}ms';
      case DeviceStatus.offline: return 'DROPPED';
      default: return 'PAUSED';
    }
  }
}
