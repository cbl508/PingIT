import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/providers/device_provider.dart';
import 'package:pingit/widgets/scan_dialog.dart';

enum SortOption { name, status, latency, health }

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({
    super.key,
    required this.devices,
    required this.groups,
    required this.isLoading,
    required this.onAddDevice,
    required this.onQuickScan,
    required this.onAddGroup,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onEditDevice,
    required this.onTapDevice,
    this.statusFilter,
    this.onStatusFilterChanged,
  });

  // These should ideally also be removed and accessed via provider,
  // but for now we keep the callbacks that trigger navigation
  final List<Device> devices;
  final List<DeviceGroup> groups;
  final bool isLoading;
  final VoidCallback onAddDevice;
  final Function(String) onQuickScan;
  final VoidCallback onAddGroup;
  final Function(DeviceGroup) onRenameGroup;
  final Function(DeviceGroup) onDeleteGroup;
  final Function(Device) onEditDevice;
  final Function(Device) onTapDevice;
  final DeviceStatus? statusFilter;
  final Function(DeviceStatus?)? onStatusFilterChanged;

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  String _searchQuery = '';
  SortOption _sortOption = SortOption.status;
  bool _isMultiSelect = false;
  final Set<String> _selectedIds = {};
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

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
      // Only select devices that are currently visible (matching search/status filters)
      final visibleDevices = widget.devices.where((d) {
        final matchesSearch =
            d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            d.address.toLowerCase().contains(_searchQuery.toLowerCase());
        bool matchesStatusFilter = true;
        if (widget.statusFilter != null) {
          if (widget.statusFilter == DeviceStatus.unknown) {
            matchesStatusFilter = d.isPaused;
          } else {
            matchesStatusFilter = d.status == widget.statusFilter && !d.isPaused;
          }
        }
        return matchesSearch && matchesStatusFilter;
      });
      _selectedIds.addAll(visibleDevices.map((d) => d.id));
    });
  }

  void _setStatusFilter(DeviceStatus? status) {
    widget.onStatusFilterChanged?.call(status);
  }

  List<Device> _getFilteredDevices(String? groupId) {
    return widget.devices.where((d) {
      final matchesGroup = d.groupId == groupId;
      final matchesSearch =
          d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          d.address.toLowerCase().contains(_searchQuery.toLowerCase());

      // Apply status filter from HUD click
      bool matchesStatusFilter = true;
      if (widget.statusFilter != null) {
        if (widget.statusFilter == DeviceStatus.unknown) {
          // "unknown" used as sentinel for paused filter
          matchesStatusFilter = d.isPaused;
        } else {
          matchesStatusFilter = d.status == widget.statusFilter && !d.isPaused;
        }
      }

      return matchesGroup && matchesSearch && matchesStatusFilter;
    }).toList()..sort((a, b) {
      switch (_sortOption) {
        case SortOption.name:
          return a.name.compareTo(b.name);
        case SortOption.status:
          if (a.status == b.status) return a.name.compareTo(b.name);
          if (a.status == DeviceStatus.offline) return -1;
          if (b.status == DeviceStatus.offline) return 1;
          if (a.status == DeviceStatus.degraded) return -1;
          if (b.status == DeviceStatus.degraded) return 1;
          return a.name.compareTo(b.name);
        case SortOption.latency:
          final cmp = (b.lastLatency ?? 0).compareTo(a.lastLatency ?? 0);
          return cmp != 0 ? cmp : a.name.compareTo(b.name);
        case SortOption.health:
          final cmp = b.stabilityScore.compareTo(a.stabilityScore);
          return cmp != 0 ? cmp : a.name.compareTo(b.name);
      }
    });
  }

  void _handleBulkPause(BuildContext context) {
    final provider = context.read<DeviceProvider>();
    final count = _selectedIds.length;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Pause $count device${count > 1 ? 's' : ''}?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('Monitoring will be paused for the selected devices.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              provider.bulkPauseDevices(_selectedIds);
              setState(() { _isMultiSelect = false; _selectedIds.clear(); });
              Navigator.pop(dialogContext);
            },
            child: const Text('Pause'),
          ),
        ],
      ),
    );
  }

  void _handleBulkResume(BuildContext context) {
    final provider = context.read<DeviceProvider>();
    final count = _selectedIds.length;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Resume $count device${count > 1 ? 's' : ''}?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('Monitoring will resume for the selected devices.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              provider.bulkResumeDevices(_selectedIds);
              setState(() { _isMultiSelect = false; _selectedIds.clear(); });
              Navigator.pop(dialogContext);
            },
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  void _completeBulkDelete(DeviceProvider provider, BuildContext dialogContext) {
    provider.bulkRemoveDevices(_selectedIds);
    setState(() {
      _isMultiSelect = false;
      _selectedIds.clear();
    });
    Navigator.pop(dialogContext);
  }

  void _handleBulkDelete(BuildContext context) {
     final provider = context.read<DeviceProvider>();
     showDialog(
      context: context,
      builder: (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () => _completeBulkDelete(provider, dialogContext),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: Text('Delete ${_selectedIds.length} devices?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            content: Text('This action cannot be undone.', style: GoogleFonts.inter()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              TextButton(
                onPressed: () => _completeBulkDelete(provider, dialogContext),
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBulkMove(BuildContext context) {
    final provider = context.read<DeviceProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Move to Group', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        children: [
          SimpleDialogOption(
            onPressed: () {
              provider.bulkMoveDevicesToGroup(_selectedIds, null);
              setState(() { _isMultiSelect = false; _selectedIds.clear(); });
              Navigator.pop(dialogContext);
            },
            child: const Text('Unassigned'),
          ),
          ...provider.groups.map((DeviceGroup g) => SimpleDialogOption(
            onPressed: () {
              provider.bulkMoveDevicesToGroup(_selectedIds, g.id);
              setState(() { _isMultiSelect = false; _selectedIds.clear(); });
              Navigator.pop(dialogContext);
            },
            child: Text(g.name),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Infrastructure Explorer',
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
                  ? () => _handleBulkPause(context)
                  : null,
              icon: const Icon(Icons.pause, size: 18),
              label: Text('Pause', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _selectedIds.isNotEmpty
                  ? () => _handleBulkResume(context)
                  : null,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text('Resume', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _selectedIds.isNotEmpty
                  ? () => _handleBulkMove(context)
                  : null,
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              label: Text('Move', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: _selectedIds.isNotEmpty
                  ? () => _handleBulkDelete(context)
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
              label: 'Scan',
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              textColor: Theme.of(context).colorScheme.primary,
              onPressed: _showScanDialog,
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
                // Status filter chip
                if (widget.statusFilter != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Chip(
                            avatar: Icon(
                              _getStatusIcon(widget.statusFilter!),
                              size: 16,
                              color: _getStatusColor(widget.statusFilter!),
                            ),
                            label: Text(
                              'Showing: ${_getStatusLabel(widget.statusFilter!)}',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _setStatusFilter(null),
                          ),
                        ],
                      ),
                    ),
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

  String _getStatusLabel(DeviceStatus status) {
    if (status == DeviceStatus.unknown) return 'PAUSED';
    return status.name.toUpperCase();
  }

  IconData _getStatusIcon(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online: return Icons.check_circle_outline;
      case DeviceStatus.degraded: return Icons.warning_amber_rounded;
      case DeviceStatus.offline: return Icons.error_outline;
      case DeviceStatus.unknown: return Icons.pause_circle_outline;
    }
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online: return const Color(0xFF10B981);
      case DeviceStatus.degraded: return const Color(0xFFF59E0B);
      case DeviceStatus.offline: return const Color(0xFFEF4444);
      case DeviceStatus.unknown: return const Color(0xFF94A3B8);
    }
  }

  void _showScanDialog() {
    showScanInputDialog(
      context: context,
      onStart: (address, type) async {
        final result = await runScanDialog(
          context: context,
          address: address,
          scanType: type,
          showAddButton: true,
        );
        if (result != null && mounted) {
          widget.onQuickScan(address);
        }
      },
    );
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
              onChanged: (val) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  setState(() => _searchQuery = val);
                });
              },
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
            DropdownMenuItem(value: SortOption.latency, child: Text('Latency')),
            DropdownMenuItem(value: SortOption.name, child: Text('Alpha')),
          ],
          onChanged: (val) => setState(() => _sortOption = val!),
        ),
      ),
    );
  }

  Widget _buildGroup(BuildContext context, DeviceGroup? group) {
    // Need to trigger saveAll when group expansion changes
    final provider = context.read<DeviceProvider>();
    final groupDevices = _getFilteredDevices(group?.id);
    if (groupDevices.isEmpty && _searchQuery.isNotEmpty) return const SizedBox.shrink();
    if (groupDevices.isEmpty && widget.statusFilter != null) return const SizedBox.shrink();
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
                      provider.saveAll(); // Save state
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
                    Row(
                      children: [
                        Flexible(child: Text(d.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: d.isPaused ? Theme.of(context).disabledColor : Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            d.checkType.name.toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(fontSize: 9, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
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
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(d.isPinned ? Icons.push_pin : Icons.push_pin_outlined, 
                      size: 18, 
                      color: d.isPinned ? Theme.of(context).colorScheme.primary : Theme.of(context).disabledColor),
                  onPressed: () {
                    d.isPinned = !d.isPinned;
                    context.read<DeviceProvider>().updateDevice(d);
                  },
                  tooltip: d.isPinned ? 'Unpin from dashboard' : 'Pin to dashboard',
                ),
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
