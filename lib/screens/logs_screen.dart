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
  int _filterIndex = 0;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    var allLogs = widget.devices
        .expand((d) => d.history.map((h) => (device: d, log: h)))
        .toList();

    if (_filterIndex == 1) {
      allLogs = allLogs
          .where((item) => item.log.status == DeviceStatus.offline)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      allLogs = allLogs
          .where(
            (item) =>
                item.device.name.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                item.device.address.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
          )
          .toList();
    }

    allLogs.sort((a, b) => b.log.timestamp.compareTo(a.log.timestamp));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Event Stream',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(140),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: SegmentedButton<int>(
                      style: SegmentedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text(
                            'Full Audit',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.visible,
                          ),
                          icon: Icon(Icons.history, size: 20),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text(
                            'Critical',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.visible,
                          ),
                          icon: Icon(Icons.emergency_outlined, size: 20),
                        ),
                      ],
                      selected: {_filterIndex},
                      onSelectionChanged: (val) =>
                          setState(() => _filterIndex = val.first),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: allLogs.length.clamp(0, 1000),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemBuilder: (context, index) {
          final item = allLogs[index];
          final isSuccess = item.log.status == DeviceStatus.online;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isSuccess ? Colors.green : Colors.red).withValues(
                  alpha: 0.1,
                ),
              ),
            ),
            child: ListTile(
              dense: true,
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (isSuccess ? Colors.green : (item.log.status == DeviceStatus.degraded ? Colors.orange : Colors.red)).withValues(
                    alpha: 0.1,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess
                      ? Icons.check_circle_outline
                      : (item.log.status == DeviceStatus.degraded ? Icons.warning_amber_rounded : Icons.error_outline),
                  color: isSuccess ? Colors.green : (item.log.status == DeviceStatus.degraded ? Colors.orange : Colors.red),
                  size: 18,
                ),
              ),
              title: Row(
                children: [
                  Text(
                    item.device.name,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('HH:mm:ss • MMM dd').format(item.log.timestamp),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              subtitle: Row(
                children: [
                  Icon(item.device.typeIcon, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    item.device.address,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isSuccess ? Colors.blue : (item.log.status == DeviceStatus.degraded ? Colors.orange : Colors.red)).withValues(
                        alpha: 0.05,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isSuccess
                          ? '${item.log.latencyMs?.toStringAsFixed(1)}ms'
                          : (item.log.status == DeviceStatus.degraded ? '${item.log.latencyMs?.toStringAsFixed(1)}ms' : 'DROPPED'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSuccess ? Colors.blue : (item.log.status == DeviceStatus.degraded ? Colors.orange : Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                onSelected: (val) {
                  if (val == 'navigate') {
                    widget.onTapDevice(item.device);
                  }
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
}
