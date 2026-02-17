import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pingit/models/device_model.dart';

enum SortOption { name, status, latency, health }

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({
    super.key,
    required this.devices,
    required this.groups,
    required this.isLoading,
    required this.onUpdate,
    required this.onGroupUpdate,
    required this.onAddDevice,
    required this.onQuickScan,
    required this.onAddGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onEditDevice,
    required this.onTapDevice,
    required this.onBulkDelete,
    required this.onBulkMoveToGroup,
  });

  final List<Device> devices;
  final List<DeviceGroup> groups;
  final bool isLoading;
  final VoidCallback onUpdate;
  final VoidCallback onGroupUpdate;
  final VoidCallback onAddDevice;
  final Function(String) onQuickScan;
  final VoidCallback onAddGroup;
  final Function(DeviceGroup) onRenameGroup;
  final Function(DeviceGroup) onDeleteGroup;
  final Function(Device) onEditDevice;
  final Function(Device) onTapDevice;
  final Function(Set<String>) onBulkDelete;
  final Function(Set<String>) onBulkMoveToGroup;

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  String _searchQuery = '';
  SortOption _sortOption = SortOption.status;
  int _touchedIndex = -1;
  bool _isMultiSelect = false;
  final Set<String> _selectedIds = {};

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelect = !_isMultiSelect;
      if (!_isMultiSelect) _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _isMultiSelect = false;
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(widget.devices.map((d) => d.id));
    });
  }

  List<Device> _getFilteredDevices(String? groupId) {
    return widget.devices.where((d) {
      final matchesGroup = d.groupId == groupId;
      final matchesSearch =
          d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          d.address.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesGroup && matchesSearch;
    }).toList()..sort((a, b) {
      switch (_sortOption) {
        case SortOption.name:
          return a.name.compareTo(b.name);
        case SortOption.status:
          if (a.status == b.status) return a.name.compareTo(b.name);
          if (a.status == DeviceStatus.offline) return -1;
          if (b.status == DeviceStatus.offline) return 1;
          return 0;
        case SortOption.latency:
          return (b.lastLatency ?? 0).compareTo(a.lastLatency ?? 0);
        case SortOption.health:
          return b.stabilityScore.compareTo(a.stabilityScore);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'PingIT Overview',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          if (_isMultiSelect) ...[
            TextButton.icon(
              onPressed: _selectAll,
              icon: const Icon(Icons.select_all, size: 18),
              label: Text('All', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _selectedIds.isNotEmpty
                  ? () => widget.onBulkMoveToGroup(_selectedIds)
                  : null,
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              label: Text('Move', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _selectedIds.isNotEmpty
                  ? () {
                      widget.onBulkDelete(_selectedIds);
                      setState(() {
                        _isMultiSelect = false;
                        _selectedIds.clear();
                      });
                    }
                  : null,
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              label: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.red)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleMultiSelect,
              tooltip: 'Cancel',
            ),
          ] else ...[
            _buildActionItem(
              context: context,
              icon: Icons.checklist_outlined,
              label: 'Select',
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: _toggleMultiSelect,
            ),
            const SizedBox(width: 8),
            _buildActionItem(
              context: context,
              icon: Icons.radar_outlined,
              label: 'Quick Scan',
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: _showQuickScanDialog,
            ),
            const SizedBox(width: 8),
            _buildActionItem(
              context: context,
              icon: Icons.create_new_folder_outlined,
              label: 'Group',
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: widget.onAddGroup,
            ),
            const SizedBox(width: 8),
            _buildActionItem(
              context: context,
              icon: Icons.add,
              label: 'New Node',
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: widget.onAddDevice,
            ),
          ],
          const SizedBox(width: 16),
        ],
      ),
      body: widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildDashboardHUD(context)
                      .animate()
                      .fade(duration: 500.ms)
                      .slideY(begin: -0.2, end: 0),
                ),
                SliverToBoxAdapter(
                  child: _buildSearchBar()
                      .animate()
                      .fade(delay: 200.ms, duration: 500.ms),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (widget.devices.isEmpty)
                        _buildEmptyState(context)
                      else ...[
                        ...widget.groups.map((g) => _buildGroup(context, g)),
                        _buildGroup(context, null),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  void _showQuickScanDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Quick Deep Scan',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a hostname or IP address to perform a comprehensive security and service scan.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.jetBrainsMono(),
              decoration: const InputDecoration(
                hintText: 'e.g. 192.168.1.1 or google.com',
                prefixIcon: Icon(Icons.public),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final addr = controller.text.trim();
                Navigator.pop(context);
                _runQuickScan(addr);
              }
            },
            child: const Text('Start Scan'),
          ),
        ],
      ),
    );
  }

  Future<void> _runQuickScan(String address) async {
    final StreamController<String> logStream = StreamController<String>();
    final List<String> lines = [
      '[SYSTEM] Initializing External Deep Scan...',
      '[TARGET] $address',
      '[CMD] nmap -sV -O -T4 $address',
      '',
      'Starting Nmap (service/OS detection)...',
    ];
    final scrollController = ScrollController();

    Process? process;
    StreamSubscription<String>? stdoutSub;
    StreamSubscription<String>? stderrSub;
    bool isClosed = false;

    void emit(String message) {
      if (!isClosed) {
        logStream.add(message);
      }
    }

    Future<void> closeStream() async {
      if (!isClosed) {
        isClosed = true;
        await logStream.close();
      }
    }

    void killProcess() {
      process?.kill();
      process = null;
    }

    try {
      process = await Process.start('nmap', ['-sV', '-O', '-T4', address],
          runInShell: Platform.isWindows);
      stdoutSub = process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          lines.add(line.trim());
          emit(line);
        }
      }, onError: (e) {
        lines.add('[SYSTEM ERR] Decoding error: $e');
        emit('ERROR');
      });
      stderrSub = process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          lines.add('[SYSTEM ERR] $line');
          emit(line);
        }
      }, onError: (e) {
        lines.add('[SYSTEM ERR] Decoding error: $e');
        emit('ERROR');
      });
      process!.exitCode.then((code) async {
        lines.add('');
        lines.add(
          code == 0
              ? '[SYSTEM] Scan completed.'
              : '[SYSTEM] Scan failed (code $code).',
        );
        emit('DONE');
        await closeStream();
      });
    } catch (e) {
      lines.add('[ERROR] "nmap" utility not found.');
      emit('ERROR');
      await closeStream();
    }
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StreamBuilder<String>(
        stream: logStream.stream,
        builder: (context, snapshot) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients) {
              scrollController.animateTo(
                scrollController.position.maxScrollExtent,
                duration: 200.ms,
                curve: Curves.easeOut,
              );
            }
          });

          return AlertDialog(
            title: Text(
              'External Infrastructure Scan',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF0F172A),
            content: Container(
              width: 700,
              height: 500,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              padding: const EdgeInsets.all(16),
              child: ListView.builder(
                controller: scrollController,
                itemCount: lines.length,
                itemBuilder: (context, i) => Text(
                  lines[i],
                  style: GoogleFonts.jetBrainsMono(
                    color: lines[i].contains('[SYSTEM ERR]')
                        ? Colors.redAccent
                        : const Color(0xFF34D399),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  killProcess();
                  Navigator.pop(context);
                },
                child: const Text('DISMISS'),
              ),
              if (snapshot.data == 'DONE')
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onQuickScan(address);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('ADD AS NODE'),
                ),
            ],
          );
        },
      ),
    );

    // Ensure process is killed when dialog closes for any reason
    killProcess();
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
    await closeStream();
    scrollController.dispose();
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 48),
          Icon(
                Icons.dns_outlined,
                size: 64,
                color: Theme.of(context).disabledColor.withValues(alpha: 0.5),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.1, duration: 2.seconds),
          const SizedBox(height: 16),
          Text(
            'No Infrastructure Monitored',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first node to start monitoring.',
            style: GoogleFonts.inter(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: widget.onAddDevice,
            icon: const Icon(Icons.add),
            label: const Text('Add Node'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      elevation: 0,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: textColor.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              style: GoogleFonts.inter(),
              decoration: InputDecoration(
                hintText: 'Search Infrastructure...',
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
          const SizedBox(width: 12),
          _buildSortDropdown(),
        ],
      ),
    );
  }

  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SortOption>(
          value: _sortOption,
          style: GoogleFonts.inter(
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
          icon: const Icon(Icons.filter_list, size: 20),
          items: const [
            DropdownMenuItem(value: SortOption.status, child: Text('Status')),
            DropdownMenuItem(value: SortOption.health, child: Text('Health')),
            DropdownMenuItem(value: SortOption.latency, child: Text('Jitter')),
            DropdownMenuItem(value: SortOption.name, child: Text('Alpha')),
          ],
          onChanged: (val) => setState(() => _sortOption = val!),
        ),
      ),
    );
  }

  Widget _buildDashboardHUD(BuildContext context) {
    final online = widget.devices
        .where((d) => d.status == DeviceStatus.online && !d.isPaused)
        .length;
    final offline = widget.devices
        .where((d) => d.status == DeviceStatus.offline && !d.isPaused)
        .length;
    final degraded = widget.devices
        .where((d) => d.status == DeviceStatus.degraded && !d.isPaused)
        .length;
    final paused = widget.devices.where((d) => d.isPaused).length;
    final total = widget.devices.length;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SYSTEM STATUS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (total > 0)
                Container(
                  width: 140,
                  height: 140,
                  margin: const EdgeInsets.only(right: 32),
                  child: Stack(
                    children: [
                      PieChart(
                        PieChartData(
                          pieTouchData: PieTouchData(
                            touchCallback: (FlTouchEvent event, pieTouchResponse) {
                              setState(() {
                                if (!event.isInterestedForInteractions ||
                                    pieTouchResponse == null ||
                                    pieTouchResponse.touchedSection == null) {
                                  _touchedIndex = -1;
                                  return;
                                }
                                _touchedIndex =
                                    pieTouchResponse.touchedSection!.touchedSectionIndex;
                              });
                            },
                          ),
                          sectionsSpace: 4,
                          centerSpaceRadius: 40,
                          sections: [
                            _buildPieSection(0, online.toDouble(), const Color(0xFF10B981), 'Online', total),
                            _buildPieSection(1, offline.toDouble(), const Color(0xFFEF4444), 'Offline', total),
                            _buildPieSection(2, degraded.toDouble(), const Color(0xFFF59E0B), 'Degraded', total),
                            _buildPieSection(3, paused.toDouble(), const Color(0xFF94A3B8), 'Paused', total),
                          ],
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$total', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                            Text('NODES', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildHUDItem('ACTIVE', '$online', const Color(0xFF10B981), Icons.check_circle_outline),
                        const SizedBox(width: 16),
                        _buildHUDItem('DEGRADED', '$degraded', const Color(0xFFF59E0B), Icons.warning_amber_rounded),
                        const SizedBox(width: 16),
                        _buildHUDItem('CRITICAL', '$offline', const Color(0xFFEF4444), Icons.error_outline),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _buildLegendItem(const Color(0xFF10B981), 'Online'),
                        const SizedBox(width: 24),
                        _buildLegendItem(const Color(0xFFF59E0B), 'Degraded'),
                        const SizedBox(width: 24),
                        _buildLegendItem(const Color(0xFFEF4444), 'Offline'),
                        const SizedBox(width: 24),
                        _buildLegendItem(const Color(0xFF94A3B8), 'Paused'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PieChartSectionData _buildPieSection(int index, double value, Color color, String label, int total) {
    final isTouched = index == _touchedIndex;
    final fontSize = isTouched ? 14.0 : 0.0;
    final radius = isTouched ? 45.0 : 35.0;
    final percentage = total > 0 ? (value / total * 100).toStringAsFixed(0) : '0';

    return PieChartSectionData(
      color: color,
      value: value,
      title: '$percentage%',
      radius: radius,
      titleStyle: GoogleFonts.inter(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.white),
      badgeWidget: isTouched ? _buildHoverTooltip(label, value.toInt()) : null,
      badgePositionPercentageOffset: .98,
    );
  }

  Widget _buildHoverTooltip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
      ),
      child: Text('$label: $count', style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12)),
      ],
    );
  }

  Widget _buildHUDItem(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 26, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(BuildContext context, DeviceGroup? group) {
    final groupDevices = _getFilteredDevices(group?.id);
    if (groupDevices.isEmpty && _searchQuery.isNotEmpty) return const SizedBox.shrink();
    if (group == null && groupDevices.isEmpty) return const SizedBox.shrink();

    return Theme(
      key: ValueKey(group?.id ?? 'unassigned'),
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (group != null || groupDevices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: group?.isExpanded ?? true,
                  onExpansionChanged: (val) {
                    if (group != null) {
                      group.isExpanded = val;
                      widget.onGroupUpdate();
                    }
                  },
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Row(
                    children: [
                      Icon(group == null ? Icons.grid_view : Icons.folder_open, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(group?.name ?? 'Unassigned Nodes', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                        child: Text('${groupDevices.length}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      if (group != null) ...[
                        const Spacer(),
                        PopupMenuButton(
                          icon: Icon(Icons.more_horiz, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          tooltip: 'Group Settings',
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'rename', child: Text('Rename Group')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete Group', style: TextStyle(color: Colors.red))),
                          ],
                          onSelected: (val) {
                            if (val == 'rename') widget.onRenameGroup(group);
                            if (val == 'delete') widget.onDeleteGroup(group);
                          },
                        ),
                      ],
                    ],
                  ),
                  children: groupDevices.map((d) => _buildNodeTile(d)).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeTile(Device d) {
    final statusColor = d.isPaused
        ? Colors.grey
        : (d.status == DeviceStatus.online
            ? const Color(0xFF10B981)
            : (d.status == DeviceStatus.degraded ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedIds.contains(d.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.15)),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey(d.id),
        onTap: _isMultiSelect ? () => _toggleSelection(d.id) : () => widget.onTapDevice(d),
        onLongPress: _isMultiSelect
            ? null
            : () {
                setState(() {
                  _isMultiSelect = true;
                  _selectedIds.add(d.id);
                });
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_isMultiSelect)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                    size: 24,
                  ),
                )
              else
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)],
                  ),
                ).animate(target: d.status == DeviceStatus.online ? 1 : 0).shimmer(
                  delay: Duration(milliseconds: 1000 + (d.hashCode % 1000)),
                  duration: 2.seconds,
                ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(d.typeIcon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: d.isPaused ? Theme.of(context).disabledColor : Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text(d.address, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              SizedBox(width: 80, height: 36, child: _buildSparkline(d)),
              const SizedBox(width: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    d.isPaused ? 'PAUSED' : (d.lastLatency != null ? '${d.lastLatency!.toStringAsFixed(1)}ms' : '--'),
                    style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w700, fontSize: 14, color: d.isPaused ? Theme.of(context).disabledColor : Theme.of(context).colorScheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      d.isPaused ? 'MAINTENANCE' : d.status.name.toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 9, color: statusColor, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              if (!_isMultiSelect) ...[
                const SizedBox(width: 16),
                Icon(Icons.chevron_right, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSparkline(Device d) {
    if (d.history.isEmpty || d.isPaused) return const SizedBox.shrink();
    final spots = d.history.reversed.take(10).toList().asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.latencyMs ?? 0);
    }).toList();

    return RepaintBoundary(
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: d.status == DeviceStatus.online
                  ? Colors.blue.withValues(alpha: 0.5)
                  : Colors.red.withValues(alpha: 0.5),
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
