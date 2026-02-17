import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/screens/add_device_screen.dart';
import 'package:pingit/widgets/scan_dialog.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

class DeviceDetailsScreen extends StatefulWidget {
  const DeviceDetailsScreen({
    super.key,
    required this.device,
    this.groups = const [],
    this.allDevices = const [],
  });

  final Device device;
  final List<DeviceGroup> groups;
  final List<Device> allDevices;

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  Timer? _refreshTimer;
  final ScrollController _chartScrollController = ScrollController();
  int _lastHistoryLength = 0;

  @override
  void initState() {
    super.initState();
    _lastHistoryLength = widget.device.history.length;
    // Refresh every 5 seconds — only rebuild if history actually changed.
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && widget.device.history.length != _lastHistoryLength) {
        _lastHistoryLength = widget.device.history.length;
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chartScrollController.hasClients) {
        _chartScrollController.jumpTo(
          _chartScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _chartScrollController.dispose();
    super.dispose();
  }

  void _editDevice() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddDeviceScreen(
          device: widget.device,
          groups: widget.groups,
          existingDevices: widget.allDevices,
        ),
      ),
    );
    if (!mounted) return;

    if (result == 'delete') {
      Navigator.of(context).pop('delete');
    } else if (result is Device) {
      if (mounted) setState(() {});
    }
  }

  void _cloneDevice() {
    final d = widget.device;
    final clone = Device(
      name: '${d.name} (Copy)',
      address: d.address,
      groupId: d.groupId,
      interval: d.interval,
      tags: List.from(d.tags),
      type: d.type,
      checkType: d.checkType,
      port: d.port,
      failureThreshold: d.failureThreshold,
      latencyThreshold: d.latencyThreshold,
      packetLossThreshold: d.packetLossThreshold,
      maxHistory: d.maxHistory,
      parentId: d.parentId,
    );
    Navigator.of(context).pop(clone);
  }

  void _showScanMenu() {
    showScanInputDialog(
      context: context,
      initialAddress: widget.device.address,
      onStart: (address, type) async {
        final result = await runScanDialog(
          context: context,
          address: address,
          scanType: type,
        );
        if (!mounted) return;
        if (result != null) {
          widget.device.lastScanResult = result.join('\n');
          setState(() {});
        }
      },
    );
  }

  Future<void> _runTraceroute() async {
    final StreamController<String> logStream = StreamController<String>();
    final List<String> lines = [
      '[SYSTEM] Initializing Node Path Analysis...',
      '[TARGET] ${widget.device.address}',
      '',
    ];
    final scrollController = ScrollController();

    final String cmd = Platform.isWindows ? 'tracert' : 'traceroute';
    Process? process;
    StreamSubscription<String>? stdoutSub;
    StreamSubscription<String>? stderrSub;
    bool isClosed = false;
    bool isDone = false;

    void emit(String message) {
      if (!isClosed) logStream.add(message);
    }

    Future<void> closeStream() async {
      if (!isClosed) { isClosed = true; await logStream.close(); }
    }

    void killProcess() {
      process?.kill();
      process = null;
    }

    try {
      process = await Process.start(cmd, [widget.device.address], runInShell: Platform.isWindows);
      stdoutSub = process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) { lines.add(line.trim()); emit(line); }
      }, onError: (e) { lines.add('[SYSTEM ERR] $e'); emit('ERROR'); });
      stderrSub = process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) { lines.add('[SYSTEM ERR] $line'); emit(line); }
      }, onError: (e) { lines.add('[SYSTEM ERR] $e'); emit('ERROR'); });
      process!.exitCode.then((code) async {
        lines.add('');
        lines.add('[SYSTEM] Analysis complete with code $code.');
        isDone = true;
        emit('DONE');
        await closeStream();
      });
    } catch (e) {
      lines.add('[ERROR] Diagnostic utility "$cmd" not found on system.');
      isDone = true;
      emit('ERROR');
      await closeStream();
    }
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => StreamBuilder<String>(
        stream: logStream.stream,
        builder: (ctx, snapshot) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients) {
              scrollController.animateTo(scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          });

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (isDone) Navigator.pop(dialogContext);
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                killProcess();
                Navigator.pop(dialogContext);
              },
            },
            child: Focus(
              autofocus: true,
              child: AlertDialog(
                title: Text('Network Path Diagnostics', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFF0F172A),
                content: Container(
                  width: 700, height: 450,
                  decoration: BoxDecoration(
                    color: Colors.black, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: lines.length,
                    itemBuilder: (context, i) => Text(lines[i],
                        style: GoogleFonts.jetBrainsMono(
                            color: lines[i].startsWith('[SYSTEM ERR]') ? Colors.redAccent : const Color(0xFF10B981),
                            fontSize: 12, height: 1.4)),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () { killProcess(); Navigator.pop(dialogContext); },
                    child: Text('DISMISS', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    killProcess();
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
    await closeStream();
    scrollController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = _calculateStats();
    final sla = _calculateSLA();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : Colors.grey.shade50,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(widget.device.typeIcon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(widget.device.name, style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ],
        ),
        actions: [
          _buildHeaderAction('Scan Host', Icons.radar_outlined, _showScanMenu),
          _buildHeaderAction('Trace', Icons.analytics_outlined, _runTraceroute),
          _buildHeaderAction('Clone', Icons.copy_outlined, _cloneDevice),
          _buildHeaderAction('Configure', Icons.edit_outlined, _editDevice),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildStabilityHeader(context, widget.device.stabilityScore)
                .animate().fade().slideY(begin: 0.1, end: 0),
            const SizedBox(height: 24),
            _buildSLACard(context, sla),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _buildHeatmap(context),
                      const SizedBox(height: 24),
                      RepaintBoundary(child: _buildChartSection(context, stats)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildStatsGrid(context, stats),
                      const SizedBox(height: 24),
                      _buildActivitySection(context),
                      if (widget.device.lastScanResult != null) ...[
                        const SizedBox(height: 24),
                        _buildScanResultSection(context),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- SLA Calculation ---

  _SLAData _calculateSLA() {
    final history = widget.device.history;
    if (history.isEmpty) return _SLAData(100, 100, 100, 100, 100, 100, Duration.zero);

    final now = DateTime.now();
    final last24h = history.where((h) => now.difference(h.timestamp).inHours < 24).toList();
    final last7d = history.where((h) => now.difference(h.timestamp).inDays < 7).toList();
    final last30d = history.where((h) => now.difference(h.timestamp).inDays < 30).toList();

    // Available = not offline (includes online + degraded)
    double available(List<StatusHistory> h) {
      if (h.isEmpty) return 100.0;
      final up = h.where((e) => e.status != DeviceStatus.offline).length;
      return (up / h.length) * 100;
    }

    // Perfect = strictly online only
    double perfect(List<StatusHistory> h) {
      if (h.isEmpty) return 100.0;
      final online = h.where((e) => e.status == DeviceStatus.online).length;
      return (online / h.length) * 100;
    }

    // Calculate total downtime from consecutive offline entries
    Duration totalDowntime = Duration.zero;
    DateTime? downStart;
    for (var h in history) {
      if (h.status == DeviceStatus.offline) {
        downStart ??= h.timestamp;
      } else if (downStart != null) {
        totalDowntime += h.timestamp.difference(downStart);
        downStart = null;
      }
    }
    if (downStart != null) {
      totalDowntime += now.difference(downStart);
    }

    return _SLAData(
      available(last24h), available(last7d), available(last30d),
      perfect(last24h), perfect(last7d), perfect(last30d),
      totalDowntime,
    );
  }

  Widget _buildSLACard(BuildContext context, _SLAData sla) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UPTIME / SLA',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 16),
          Text('AVAILABLE (non-offline)',
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSLAMetric(context, '24h', sla.avail24h),
              const SizedBox(width: 16),
              _buildSLAMetric(context, '7 days', sla.avail7d),
              const SizedBox(width: 16),
              _buildSLAMetric(context, '30 days', sla.avail30d),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL DOWNTIME',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(_formatDuration(sla.totalDowntime),
                        style: GoogleFonts.jetBrainsMono(fontSize: 18, fontWeight: FontWeight.w700,
                            color: sla.totalDowntime.inMinutes > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('PERFECT UPTIME (online only)',
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSLAMetric(context, '24h', sla.perfect24h),
              const SizedBox(width: 16),
              _buildSLAMetric(context, '7 days', sla.perfect7d),
              const SizedBox(width: 16),
              _buildSLAMetric(context, '30 days', sla.perfect30d),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSLAMetric(BuildContext context, String label, double uptime) {
    Color color = uptime >= 99.9 ? const Color(0xFF10B981) : (uptime >= 99 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
    return Column(
      children: [
        Text('${uptime.toStringAsFixed(2)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  // --- Existing UI builders ---

  Widget _buildScanResultSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('LAST DEEP SCAN REPORT', style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1)),
            const Spacer(),
            const Icon(Icons.history, size: 14, color: Colors.grey),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
            child: Text(widget.device.lastScanResult!,
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF34D399), height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildStabilityHeader(BuildContext context, double score) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color scoreColor = score >= 90 ? const Color(0xFF10B981) : (score >= 70 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120, height: 120,
                child: CircularProgressIndicator(
                  value: score / 100, strokeWidth: 12,
                  backgroundColor: scoreColor.withValues(alpha: 0.1), color: scoreColor, strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(score.toStringAsFixed(0),
                      style: GoogleFonts.jetBrainsMono(fontSize: 36, fontWeight: FontWeight.w900, color: scoreColor, letterSpacing: -1)),
                  Text('%', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('RELIABILITY SCORE',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text('70% uptime + 30% packet loss reliability',
              style: GoogleFonts.inter(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildHeatmap(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = widget.device.history.length > 60
        ? widget.device.history.sublist(widget.device.history.length - 60)
        : widget.device.history;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STATUS HISTORY (LAST 60 TICKS)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1)),
        const SizedBox(height: 16),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).cardTheme.color,
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: history.isEmpty
                ? [Expanded(child: Center(child: Text('Awaiting data stream...', style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).disabledColor))))]
                : history.map((h) {
                    Color color = h.status == DeviceStatus.offline
                        ? const Color(0xFFEF4444)
                        : ((h.latencyMs ?? 0) > 200 ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
                    return Expanded(
                      child: Tooltip(
                        message: '${DateFormat('yyyy-MM-dd HH:mm:ss').format(h.timestamp)}\n${h.status.name.toUpperCase()} - ${h.latencyMs?.toStringAsFixed(1) ?? 0}ms',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, _DeviceStats stats) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _buildStatCard('LATENCY (AVG)', '${stats.avgLatency.toStringAsFixed(1)}ms', Icons.speed)),
          const SizedBox(width: 16),
          Expanded(child: _buildStatCard('PACKET LOSS', '${stats.avgLoss.toStringAsFixed(0)}%', Icons.leak_add)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _buildStatCard('PEAK JITTER', '${stats.maxLatency.toStringAsFixed(1)}ms', Icons.trending_up)),
          const SizedBox(width: 16),
          Expanded(child: _buildStatCard('SAMPLE COUNT', '${widget.device.history.length}', Icons.data_usage)),
        ]),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 16),
          Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildChartSection(BuildContext context, _DeviceStats stats) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spots = _getSpots();
    final double dynamicWidth = max(600.0, widget.device.history.length * 30.0);

    double yInterval = 1.0;
    if (stats.maxLatency > 0) {
      yInterval = (stats.maxLatency / 5).clamp(0.1, double.infinity);
      if (yInterval > 1) yInterval = yInterval.roundToDouble();
    }

    return Container(
      height: 500,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LATENCY DISTRIBUTION',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 24),
          Expanded(
            child: Scrollbar(
              controller: _chartScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _chartScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: dynamicWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 40, bottom: 4),
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: stats.maxLatency * 1.2 + 1,
                        clipData: const FlClipData.all(),
                        gridData: FlGridData(
                          show: true, drawVerticalLine: false,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05), strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            axisNameWidget: Text('TIME OF PING',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            axisNameSize: 20,
                            sideTitles: SideTitles(
                              showTitles: true, reservedSize: 60, interval: max(5, (widget.device.history.length / 8).roundToDouble()),
                              getTitlesWidget: (v, m) {
                                if (v.toInt() >= 0 && v.toInt() < widget.device.history.length) {
                                  final time = widget.device.history[v.toInt()].timestamp;
                                  return SideTitleWidget(
                                    meta: m, space: 12,
                                    child: Transform.rotate(
                                      angle: -0.5,
                                      child: Text(DateFormat('MM/dd HH:mm').format(time),
                                          style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            axisNameWidget: Text('LATENCY (ms)',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            axisNameSize: 25,
                            sideTitles: SideTitles(
                              showTitles: true, reservedSize: 50, interval: yInterval,
                              getTitlesWidget: (v, m) => SideTitleWidget(meta: m,
                                  child: Text(v.toStringAsFixed(1),
                                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                            left: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (spot) => const Color(0xFF1E293B),
                            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                if (spot.x.toInt() >= 0 && spot.x.toInt() < widget.device.history.length) {
                                  final historyItem = widget.device.history[spot.x.toInt()];
                                  final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(historyItem.timestamp);
                                  return LineTooltipItem('$timeStr\n${spot.y.toStringAsFixed(1)} ms',
                                      GoogleFonts.jetBrainsMono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12));
                                }
                                return null;
                              }).toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots, isCurved: true, curveSmoothness: 0.2,
                            color: Theme.of(context).colorScheme.primary, barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.0),
                                ],
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recent = widget.device.history.reversed.take(15).toList();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LIVE EVENT STREAM', style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length,
            separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 24),
            itemBuilder: (context, index) {
              final h = recent[index];
              return Row(
                children: [
                  Icon(Icons.circle, size: 8, color: h.status == DeviceStatus.online ? Colors.green : Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.status == DeviceStatus.online ? 'REPLY RECEIVED' : 'REQUEST TIMED OUT',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(h.timestamp),
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text(h.latencyMs != null ? '${h.latencyMs!.toStringAsFixed(1)}ms' : '0.0ms',
                      style: GoogleFonts.jetBrainsMono(fontSize: 11)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<FlSpot> _getSpots() {
    return List.generate(widget.device.history.length, (i) {
      return FlSpot(i.toDouble(), widget.device.history[i].latencyMs ?? 0.0);
    });
  }

  _DeviceStats _calculateStats() {
    if (widget.device.history.isEmpty) return _DeviceStats(0, 0, 0, 0, 0);
    final online = widget.device.history.where((h) => h.status == DeviceStatus.online).toList();
    final uptime = (online.length / widget.device.history.length) * 100;
    double totalLatency = 0, maxLatency = 0, minLatency = double.infinity, totalLoss = 0;
    for (var h in widget.device.history) {
      totalLatency += h.latencyMs ?? 0;
      totalLoss += h.packetLoss ?? 100;
      if ((h.latencyMs ?? 0) > maxLatency) maxLatency = h.latencyMs!;
      if ((h.latencyMs ?? 0) < minLatency && h.status == DeviceStatus.online) minLatency = h.latencyMs!;
    }
    if (minLatency == double.infinity) minLatency = 0;
    return _DeviceStats(
      uptime,
      online.isEmpty ? 0 : totalLatency / online.length,
      maxLatency, minLatency,
      totalLoss / widget.device.history.length,
    );
  }
}

class _DeviceStats {
  final double uptime, avgLatency, maxLatency, minLatency, avgLoss;
  _DeviceStats(this.uptime, this.avgLatency, this.maxLatency, this.minLatency, this.avgLoss);
}

class _SLAData {
  final double avail24h, avail7d, avail30d;
  final double perfect24h, perfect7d, perfect30d;
  final Duration totalDowntime;
  _SLAData(this.avail24h, this.avail7d, this.avail30d, this.perfect24h, this.perfect7d, this.perfect30d, this.totalDowntime);
}
