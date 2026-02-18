import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pingit/models/device_model.dart';

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
  String _searchQuery = '';
  DeviceStatus? _statusFilter;
  final Map<String, int> _pageSizeMap = {};
  final Map<String, DeviceStatus?> _deviceStatusFilterMap = {};
  static const int _initialPageSize = 20;

  List<Device> _getFilteredDevices() {
    return widget.devices.where((d) {
      final matchesSearch = d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          d.address.toLowerCase().contains(_searchQuery.toLowerCase());
      
      bool matchesStatus = true;
      if (_statusFilter != null) {
        matchesStatus = d.status == _statusFilter;
      }
      
      return matchesSearch && matchesStatus;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _exportAllCsv() async {
    final buffer = StringBuffer();
    buffer.writeln('Device,Address,Timestamp,Status,Latency (ms),Packet Loss (%),Response Code');
    
    int count = 0;
    for (final device in widget.devices) {
      for (final h in device.history.reversed) {
        final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(h.timestamp);
        final latency = h.latencyMs?.toStringAsFixed(1) ?? '';
        final loss = h.packetLoss?.toStringAsFixed(1) ?? '';
        final code = h.responseCode?.toString() ?? '';
        final name = device.name.contains(',') ? '"${device.name}"' : device.name;
        buffer.writeln('$name,${device.address},$ts,${h.status.name},$latency,$loss,$code');
        count++;
      }
    }

    if (count == 0) return;

    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export All Event Logs',
        fileName: 'pingit_all_logs_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result != null) {
        await File(result).writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported $count events across all nodes')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _exportDeviceCsv(Device device) async {
    if (device.history.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('Timestamp,Status,Latency (ms),Packet Loss (%),Response Code');
    for (final h in device.history.reversed) {
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(h.timestamp);
      final latency = h.latencyMs?.toStringAsFixed(1) ?? '';
      final loss = h.packetLoss?.toStringAsFixed(1) ?? '';
      final code = h.responseCode?.toString() ?? '';
      buffer.writeln('$ts,${h.status.name},$latency,$loss,$code');
    }

    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Logs: ${device.name}',
        fileName: 'logs_${device.name.replaceAll(RegExp(r'[^\w]'), '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result != null) {
        await File(result).writeAsString(buffer.toString());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported ${device.history.length} events for ${device.name}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredDevices = _getFilteredDevices();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Infrastructure Logs',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: _exportAllCsv,
            tooltip: 'Export All Logs',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: filteredDevices.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: filteredDevices.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) => _buildDeviceLogCard(filteredDevices[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
      ),
      child: Column(
        children: [
          TextField(
            style: GoogleFonts.inter(),
            decoration: InputDecoration(
              hintText: 'Search nodes...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F172A) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip(null, 'All Nodes', Icons.hub_outlined, Colors.blueGrey),
                const SizedBox(width: 8),
                _buildStatusChip(DeviceStatus.online, 'Online', Icons.check_circle_outline, Colors.green),
                const SizedBox(width: 8),
                _buildStatusChip(DeviceStatus.degraded, 'Degraded', Icons.warning_amber_rounded, Colors.orange),
                const SizedBox(width: 8),
                _buildStatusChip(DeviceStatus.offline, 'Offline', Icons.error_outline, Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(DeviceStatus? status, String label, IconData icon, Color color) {
    final isSelected = _statusFilter == status;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(icon, size: 14, color: isSelected ? Colors.white : color),
      label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : null)),
      selectedColor: color,
      onSelected: (_) => setState(() => _statusFilter = status),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildDeviceLogCard(Device device) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getDeviceStatusColor(device.status);
    final historyCount = device.history.length;
    final displayLimit = _pageSizeMap[device.id] ?? _initialPageSize;
    final deviceFilter = _deviceStatusFilterMap[device.id];

    // Calculate stats for this device
    final stats = _calculateDeviceStats(device);

    // Filter history for display
    final filteredHistory = device.history.reversed.where((h) {
      if (deviceFilter == null) return true;
      return h.status == deviceFilter;
    }).toList();

    final displayedHistory = filteredHistory.take(displayLimit).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: ExpansionTile(
        key: PageStorageKey('logs_exp_${device.id}'),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(device.typeIcon, color: statusColor, size: 20),
        ),
        title: Text(
          device.name,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Row(
          children: [
            Text(device.address, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.grey)),
            const Spacer(),
            Text(
              '$historyCount events',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey),
            ),
          ],
        ),
        children: [
          const Divider(height: 1),
          // --- Statistics Row ---
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.grey.withValues(alpha: 0.02),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCompactStat('UPTIME', '${stats.uptime.toStringAsFixed(1)}%', 
                    stats.uptime < 95 ? Colors.red : (stats.uptime < 99 ? Colors.orange : Colors.green)),
                _buildCompactStat('AVG LATENCY', '${stats.avgLatency.toStringAsFixed(1)}ms', null),
                _buildCompactStat('PEAK', '${stats.maxLatency.toStringAsFixed(1)}ms', 
                    stats.maxLatency > 500 ? Colors.orange : null),
              ],
            ),
          ),
          const Divider(height: 1),
          // --- Per-Device Filter Bar ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMiniFilterChip(device.id, null, 'All', Colors.blueGrey),
                _buildMiniFilterChip(device.id, DeviceStatus.online, 'Online', Colors.green),
                _buildMiniFilterChip(device.id, DeviceStatus.degraded, 'Degraded', Colors.orange),
                _buildMiniFilterChip(device.id, DeviceStatus.offline, 'Offline', Colors.red),
              ],
            ),
          ),
          const Divider(height: 1),
          if (filteredHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                deviceFilter == null ? 'No events recorded yet' : 'No ${deviceFilter.name} events found',
                style: GoogleFonts.inter(color: Colors.grey),
              ),
            )
          else ...[
            // Using Column instead of ListView to avoid Scrollable/PageStorage conflicts
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: List.generate(displayedHistory.length * 2 - 1, (index) {
                  if (index.isOdd) {
                    return Divider(height: 1, indent: 20, endIndent: 20, color: Colors.grey.withValues(alpha: 0.05));
                  }
                  final h = displayedHistory[index ~/ 2];
                  return _buildHistoryItem(h);
                }),
              ),
            ),
            if (filteredHistory.length > displayLimit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _pageSizeMap[device.id] = displayLimit + 50;
                    });
                  },
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: Text('Load older events (${filteredHistory.length - displayLimit} remaining)'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _exportDeviceCsv(device),
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Export History'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => widget.onTapDevice(device),
                    icon: const Icon(Icons.analytics_outlined, size: 16),
                    label: const Text('Node Details'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryItem(StatusHistory h) {
    final color = _getDeviceStatusColor(h.status);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Row(
        children: [
          Text(
            h.status.name.toUpperCase(),
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5),
          ),
          const Spacer(),
          Text(
            DateFormat('HH:mm:ss \u2022 MMM dd').format(h.timestamp),
            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          _getStatusDetail(h),
          style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  String _getStatusDetail(StatusHistory h) {
    final parts = <String>[];
    if (h.latencyMs != null) parts.add('${h.latencyMs!.toStringAsFixed(1)}ms latency');
    if (h.packetLoss != null && h.packetLoss! > 0) parts.add('${h.packetLoss!.toStringAsFixed(0)}% loss');
    if (h.responseCode != null) parts.add('HTTP ${h.responseCode}');
    
    if (parts.isEmpty) {
      return h.status == DeviceStatus.online ? 'Healthy connection' : 'Connection failed';
    }
    return parts.join(' \u2022 ');
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No nodes found', style: GoogleFonts.inter(color: Colors.grey)),
        ],
      ),
    );
  }

  Color _getDeviceStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online: return Colors.green;
      case DeviceStatus.degraded: return Colors.orange;
      case DeviceStatus.offline: return Colors.red;
      default: return Colors.blueGrey;
    }
  }

  Widget _buildMiniFilterChip(String deviceId, DeviceStatus? status, String label, Color color) {
    final isSelected = _deviceStatusFilterMap[deviceId] == status;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? Colors.white : color,
        ),
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: color,
      onSelected: (_) {
        setState(() {
          _deviceStatusFilterMap[deviceId] = status;
          _pageSizeMap[deviceId] = _initialPageSize; // Reset page size on filter change
        });
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildCompactStat(String label, String value, Color? valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.grey,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  _SimplifiedDeviceStats _calculateDeviceStats(Device device) {
    if (device.history.isEmpty) return _SimplifiedDeviceStats(100, 0, 0);
    
    final onlineCount = device.history.where((h) => h.status == DeviceStatus.online).length;
    final uptime = (onlineCount / device.history.length) * 100;
    
    double totalLatency = 0;
    double maxLatency = 0;
    int responded = 0;
    
    for (var h in device.history) {
      if (h.latencyMs != null && h.latencyMs! > 0) {
        totalLatency += h.latencyMs!;
        if (h.latencyMs! > maxLatency) maxLatency = h.latencyMs!;
        responded++;
      }
    }
    
    return _SimplifiedDeviceStats(
      uptime,
      responded == 0 ? 0 : totalLatency / responded,
      maxLatency,
    );
  }
}

class _SimplifiedDeviceStats {
  final double uptime;
  final double avgLatency;
  final double maxLatency;
  _SimplifiedDeviceStats(this.uptime, this.avgLatency, this.maxLatency);
}
