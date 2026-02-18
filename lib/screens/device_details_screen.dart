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
import 'package:dart_ping/dart_ping.dart';
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
  final ScrollController _consoleScrollController = ScrollController();
  int _lastHistoryLength = 0;

  // ── Manual ping state ──
  bool _isPinging = false;
  final List<_PingResult> _pingResults = [];
  Ping? _activePing;
  StreamSubscription? _pingSubscription;
  Process? _pingProcess;
  StreamSubscription? _pingStdoutSub;

  @override
  void initState() {
    super.initState();
    _lastHistoryLength = widget.device.history.length;
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && widget.device.history.length != _lastHistoryLength) {
        _lastHistoryLength = widget.device.history.length;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToEnd(_chartScrollController, animate: true);
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEnd(_chartScrollController);
    });
  }

  void _scrollToEnd(ScrollController c, {bool animate = false}) {
    if (!c.hasClients) return;
    if (animate) {
      c.animateTo(c.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      c.jumpTo(c.position.maxScrollExtent);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _chartScrollController.dispose();
    _consoleScrollController.dispose();
    _stopPing(silent: true);
    super.dispose();
  }

  // ───────────────────────── Actions ─────────────────────────

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

  // ── Manual ping controls ──

  void _clearConsole() {
    setState(() => _pingResults.clear());
  }

  void _startPing() {
    setState(() => _isPinging = true);

    if (Platform.isWindows) {
      _startPingWindows();
    } else {
      _startPingNative();
    }
  }

  void _startPingNative() {
    int seq = 0;
    _activePing = Ping(widget.device.address, count: 99999, timeout: 2);
    _pingSubscription = _activePing!.stream.listen(
      (event) {
        if (!_isPinging || !mounted) return;
        if (event.summary != null) return;
        seq++;
        final time = event.response?.time;
        _addPingResult(seq, time != null ? time.inMicroseconds / 1000.0 : null);
      },
      onDone: () {
        if (mounted && _isPinging) setState(() => _isPinging = false);
      },
      onError: (_) {
        if (mounted && _isPinging) setState(() => _isPinging = false);
      },
    );
  }

  void _startPingWindows() async {
    int seq = 0;
    final latencyRegex = RegExp(r'[=<]\s*(\d+)\s*ms', caseSensitive: false);
    try {
      _pingProcess = await Process.start('ping', ['-t', '-w', '2000', widget.device.address]);
      _pingStdoutSub = _pingProcess!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (!_isPinging || !mounted) return;
        final upper = line.toUpperCase();
        if (upper.contains('TTL')) {
          seq++;
          final match = latencyRegex.firstMatch(line);
          _addPingResult(seq, match != null ? double.parse(match.group(1)!) : null);
        } else if (upper.contains('TIMED OUT') ||
            upper.contains('UNREACHABLE') ||
            upper.contains('GENERAL FAILURE')) {
          seq++;
          _addPingResult(seq, null);
        }
      });
      _pingProcess!.exitCode.then((_) {
        if (mounted && _isPinging) setState(() => _isPinging = false);
      });
    } catch (_) {
      if (mounted) setState(() => _isPinging = false);
    }
  }

  void _stopPing({bool silent = false}) {
    _activePing?.stop();
    _pingSubscription?.cancel();
    _pingProcess?.kill();
    _pingStdoutSub?.cancel();
    _activePing = null;
    _pingSubscription = null;
    _pingProcess = null;
    _pingStdoutSub = null;
    _isPinging = false;
    if (!silent && mounted) setState(() {});
  }

  void _addPingResult(int seq, double? latencyMs) {
    if (!mounted) return;
    setState(() {
      _pingResults.add(_PingResult(seq: seq, latencyMs: latencyMs, timestamp: DateTime.now()));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEnd(_consoleScrollController, animate: true);
    });
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

  // ───────────────────────── Build ─────────────────────────

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
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(widget.device.address,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary)),
            ),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Row 1: compact status bar ──
            _buildStatusBar(context, stats, sla)
                .animate().fade().slideY(begin: 0.05, end: 0),
            const SizedBox(height: 16),
            // ── Row 2: heatmap ──
            _buildHeatmap(context),
            const SizedBox(height: 16),
            // ── Row 3: chart + console ──
            SizedBox(
              height: 520,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: RepaintBoundary(child: _buildChartSection(context, stats))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildConsole(context)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Row 4: SLA detail bar ──
            _buildSLABar(context, sla),
            // ── Row 5: scan results ──
            if (widget.device.lastScanResult != null) ...[
              const SizedBox(height: 16),
              _buildScanResultSection(context),
            ],
          ],
        ),
      ),
    );
  }

  // ───────────────────── Status bar ─────────────────────

  Widget _buildStatusBar(BuildContext context, _DeviceStats stats, _SLAData sla) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final score = widget.device.stabilityScore;
    final scoreColor = score >= 90
        ? const Color(0xFF10B981)
        : (score >= 70 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    Color statusColor;
    String statusLabel;
    switch (widget.device.status) {
      case DeviceStatus.online:
        statusColor = const Color(0xFF10B981);
        statusLabel = 'ONLINE';
      case DeviceStatus.offline:
        statusColor = const Color(0xFFEF4444);
        statusLabel = 'OFFLINE';
      case DeviceStatus.degraded:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'DEGRADED';
      case DeviceStatus.unknown:
        statusColor = Colors.grey;
        statusLabel = 'UNKNOWN';
    }

    Widget divider() => Container(
          width: 1,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.12),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          // Score ring
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 4.5,
                  backgroundColor: scoreColor.withValues(alpha: 0.12),
                  color: scoreColor,
                  strokeCap: StrokeCap.round,
                ),
                Text(score.toStringAsFixed(0),
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 15, fontWeight: FontWeight.w900, color: scoreColor)),
              ],
            ),
          ),
          divider(),
          // Key metrics
          _buildMetric('AVG LATENCY', '${stats.avgLatency.toStringAsFixed(1)}ms', context),
          const SizedBox(width: 24),
          _buildMetric('PACKET LOSS', '${stats.avgLoss.toStringAsFixed(0)}%', context,
              valueColor: stats.avgLoss > 5 ? const Color(0xFFEF4444) : null),
          const SizedBox(width: 24),
          _buildMetric('PEAK', '${stats.maxLatency.toStringAsFixed(1)}ms', context),
          const SizedBox(width: 24),
          _buildMetric('SAMPLES', '${widget.device.history.length}', context),
          divider(),
          _buildMetric('UPTIME 24H', '${sla.perfect24h.toStringAsFixed(1)}%', context,
              valueColor: sla.perfect24h < 99 ? const Color(0xFFEF4444) : null),
          const SizedBox(width: 24),
          _buildMetric('DOWNTIME', _formatDuration(sla.totalDowntime), context,
              valueColor: sla.totalDowntime.inMinutes > 0 ? const Color(0xFFEF4444) : null),
          const Spacer(),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(statusLabel,
                    style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w800, color: statusColor, letterSpacing: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, BuildContext context, {Color? valueColor}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: valueColor ?? Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.5)),
      ],
    );
  }

  // ───────────────────── Heatmap ─────────────────────

  Widget _buildHeatmap(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = widget.device.history.length > 60
        ? widget.device.history.sublist(widget.device.history.length - 60)
        : widget.device.history;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).cardTheme.color,
        border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STATUS HISTORY (LAST 60 TICKS)',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          SizedBox(
            height: 22,
            child: Row(
              children: history.isEmpty
                  ? [
                      Expanded(
                          child: Center(
                              child: Text('Awaiting data...',
                                  style: GoogleFonts.inter(
                                      fontSize: 10, color: Theme.of(context).disabledColor))))
                    ]
                  : history.map((h) {
                      Color color;
                      final hasResponse = h.latencyMs != null && h.latencyMs! > 0;
                      if (!hasResponse || h.status == DeviceStatus.offline) {
                        color = const Color(0xFFEF4444);
                      } else if (h.status == DeviceStatus.degraded || h.latencyMs! > 200) {
                        color = const Color(0xFFF59E0B);
                      } else {
                        color = const Color(0xFF10B981);
                      }
                      final latencyStr = hasResponse ? '${h.latencyMs!.toStringAsFixed(1)}ms' : '---';
                      return Expanded(
                        child: Tooltip(
                          message:
                              '${DateFormat('yyyy-MM-dd HH:mm:ss').format(h.timestamp)}\n${hasResponse ? h.status.name.toUpperCase() : 'OFFLINE'} — $latencyStr',
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration:
                                BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      );
                    }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── Chart ─────────────────────

  static const _kOnline = Color(0xFF10B981);
  static const _kDegraded = Color(0xFFF59E0B);
  static const _kOffline = Color(0xFFEF4444);

  Color _statusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online:
        return _kOnline;
      case DeviceStatus.degraded:
        return _kDegraded;
      case DeviceStatus.offline:
        return _kOffline;
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  Widget _legendDash(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 1.5, color: color),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  Widget _buildChartSection(BuildContext context, _DeviceStats stats) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = widget.device.history;
    final double dynamicWidth = max(600.0, history.length * 24.0);

    final yInterval = _niceInterval(stats.maxLatency, 5);
    final chartMaxY = stats.maxLatency > 0
        ? ((stats.maxLatency / yInterval).ceil() + 1) * yInterval
        : 1.0;

    // Single line — real latency for online/degraded, 0 for offline.
    // No NaN anywhere — eliminates fl_chart NaN crashes in gradient/tooltip.
    final spots = List.generate(history.length, (i) {
      final latency = history[i].latencyMs;
      return FlSpot(i.toDouble(), (latency != null && latency > 0) ? latency : 0.0);
    });

    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.04);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final avgLineColor = isDark ? Colors.white38 : Colors.black26;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title + legend
          Row(
            children: [
              Text('LATENCY DISTRIBUTION (ms)',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 1)),
              const Spacer(),
              _legendDot(_kOnline, 'Online'),
              const SizedBox(width: 10),
              _legendDot(_kDegraded, 'Degraded'),
              const SizedBox(width: 10),
              _legendDot(_kOffline, 'Offline'),
              if (stats.avgLatency > 0) ...[
                const SizedBox(width: 10),
                _legendDash(avgLineColor, 'Avg ${stats.avgLatency.toStringAsFixed(1)}ms'),
              ],
            ],
          ),
          const SizedBox(height: 16),
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
                    padding: const EdgeInsets.only(right: 30, bottom: 4),
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: chartMaxY,
                        clipData: const FlClipData.all(),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: yInterval,
                          getDrawingHorizontalLine: (v) =>
                              FlLine(color: gridColor, strokeWidth: 1),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            if (stats.avgLatency > 0)
                              HorizontalLine(
                                y: stats.avgLatency,
                                color: avgLineColor,
                                strokeWidth: 1,
                                dashArray: [6, 4],
                                label: HorizontalLineLabel(
                                  show: true,
                                  alignment: Alignment.topRight,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                  labelResolver: (_) =>
                                      'avg ${stats.avgLatency.toStringAsFixed(1)}ms',
                                ),
                              ),
                          ],
                        ),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            axisNameSize: 18,
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              interval: max(5, (history.length / 8).roundToDouble()),
                              getTitlesWidget: (v, m) {
                                if (v.toInt() >= 0 && v.toInt() < history.length) {
                                  final time = history[v.toInt()].timestamp;
                                  return SideTitleWidget(
                                    meta: m,
                                    space: 10,
                                    child: Transform.rotate(
                                      angle: -0.5,
                                      child: Text(DateFormat('MM/dd HH:mm').format(time),
                                          style: GoogleFonts.jetBrainsMono(
                                              fontSize: 9,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant)),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            axisNameSize: 22,
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 46,
                              interval: yInterval,
                              getTitlesWidget: (v, m) => SideTitleWidget(
                                  meta: m,
                                  child: Text(
                                      yInterval >= 1
                                          ? v.toStringAsFixed(
                                              v == v.roundToDouble() ? 0 : 1)
                                          : v.toStringAsFixed(1),
                                      style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant))),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(color: borderColor),
                            left: BorderSide(color: borderColor),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          getTouchedSpotIndicator: (barData, spotIndexes) {
                            return spotIndexes.map((i) {
                              final spot = barData.spots[i];
                              final idx = spot.x.toInt();
                              final color = (idx >= 0 && idx < history.length)
                                  ? _statusColor(history[idx].status)
                                  : _kOnline;
                              return TouchedSpotIndicatorData(
                                FlLine(
                                  color: isDark ? Colors.white24 : Colors.black12,
                                  strokeWidth: 1,
                                  dashArray: [4, 4],
                                ),
                                FlDotData(
                                    show: true,
                                    getDotPainter: (s, _, __, ___) =>
                                        FlDotCirclePainter(
                                          radius: 5,
                                          color: color,
                                          strokeColor: Colors.white,
                                          strokeWidth: 2,
                                        )),
                              );
                            }).toList();
                          },
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) =>
                                isDark ? const Color(0xFF1E293B) : Colors.white,
                            tooltipPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            tooltipBorder:
                                BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                final idx = spot.x.toInt();
                                if (idx < 0 || idx >= history.length) return null;
                                final h = history[idx];
                                final timeStr =
                                    DateFormat('HH:mm:ss').format(h.timestamp);
                                final textColor =
                                    isDark ? Colors.white : Colors.black87;
                                final isOffline =
                                    h.status == DeviceStatus.offline;

                                if (isOffline) {
                                  return LineTooltipItem(
                                    'OFFLINE\n$timeStr',
                                    GoogleFonts.jetBrainsMono(
                                        color: _kOffline,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11),
                                  );
                                }

                                final statusStr = h.status.name.toUpperCase();
                                final latencyStr =
                                    h.latencyMs != null && h.latencyMs! > 0
                                        ? '${h.latencyMs!.toStringAsFixed(1)}ms'
                                        : '---';
                                final lossStr = (h.packetLoss ?? 0) > 0
                                    ? '  ${h.packetLoss!.toStringAsFixed(0)}% loss'
                                    : '';
                                return LineTooltipItem(
                                  '$statusStr  $latencyStr$lossStr\n$timeStr',
                                  GoogleFonts.jetBrainsMono(
                                      color: textColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: 0.15,
                            preventCurveOverShooting: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 2,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, _, __, ___) {
                                final idx = spot.x.toInt();
                                final color = (idx >= 0 && idx < history.length)
                                    ? _statusColor(history[idx].status)
                                    : _kOnline;
                                return FlDotCirclePainter(
                                  radius: 3.5,
                                  color: color,
                                  strokeColor: isDark
                                      ? const Color(0xFF020617)
                                      : Colors.white,
                                  strokeWidth: 1.5,
                                );
                              },
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.1),
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
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

  // ───────────────────── Console ─────────────────────

  Widget _buildConsole(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final addr = widget.device.address;
    final results = _pingResults;
    final hasResults = results.isNotEmpty;
    final stopped = !_isPinging && hasResults;

    // Theme-aware console colors
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final barColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF3F8);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFD5DCE5);
    final mutedColor = cs.onSurfaceVariant;
    final replyColor = isDark ? const Color(0xFF3FB950) : const Color(0xFF16A34A);
    final timeoutColor = isDark ? const Color(0xFFF85149) : const Color(0xFFDC2626);

    // Summary stats
    final replied = results.where((r) => r.latencyMs != null).toList();
    final lossP = hasResults ? ((results.length - replied.length) / results.length * 100) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Title bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: barColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 15, color: mutedColor),
                const SizedBox(width: 10),
                Text('PING',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, fontWeight: FontWeight.w700, color: mutedColor)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(addr,
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: mutedColor),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                // Clear button
                if (hasResults && !_isPinging)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _consoleButton('Clear', Icons.delete_outline_rounded, mutedColor, _clearConsole),
                  ),
                // Start / Stop button
                _isPinging
                    ? _consoleButton('Stop', Icons.stop_rounded, timeoutColor, _stopPing)
                    : _consoleButton('Start', Icons.play_arrow_rounded, replyColor, _startPing),
              ],
            ),
          ),
          // ── Body ──
          Expanded(
            child: !hasResults && !_isPinging
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sensors_rounded,
                            size: 28, color: cs.onSurface.withValues(alpha: 0.06)),
                        const SizedBox(height: 12),
                        Text('Press Start to begin',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 12, color: mutedColor.withValues(alpha: 0.5))),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _consoleScrollController,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    itemCount: results.length + 1 + (stopped ? 1 : 0),
                    itemBuilder: (context, index) {
                      // ── Header ──
                      if (index == 0) {
                        return Text(
                          '\$ ping $addr\nICMP  interval=1s\n',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, color: mutedColor, height: 1.5),
                        );
                      }
                      // ── Summary footer (only when stopped) ──
                      if (stopped && index == results.length + 1) {
                        final avgMs = replied.isEmpty
                            ? 0.0
                            : replied.fold<double>(0, (s, r) => s + r.latencyMs!) / replied.length;
                        final minMs = replied.isEmpty
                            ? 0.0
                            : replied.fold<double>(
                                double.infinity, (m, r) => min(m, r.latencyMs!));
                        final maxMs = replied.isEmpty
                            ? 0.0
                            : replied.fold<double>(0, (m, r) => max(m, r.latencyMs!));
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '--- $addr ping statistics ---\n'
                            '${results.length} transmitted, ${replied.length} received, '
                            '${lossP.toStringAsFixed(0)}% loss\n'
                            'rtt min/avg/max = '
                            '${minMs.toStringAsFixed(1)}/'
                            '${avgMs.toStringAsFixed(1)}/'
                            '${maxMs.toStringAsFixed(1)} ms',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                height: 1.5,
                                color: lossP > 50
                                    ? timeoutColor.withValues(alpha: 0.7)
                                    : mutedColor),
                          ),
                        );
                      }
                      // ── Ping result line ──
                      final r = results[index - 1];
                      final ts = DateFormat('HH:mm:ss').format(r.timestamp);

                      if (r.latencyMs != null) {
                        return Text(
                          '$ts  reply  seq=${r.seq}  time=${r.latencyMs!.toStringAsFixed(1)}ms',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, height: 1.6, color: replyColor),
                        );
                      } else {
                        return Text(
                          '$ts  request timeout  seq=${r.seq}',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 11, height: 1.6, color: timeoutColor),
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _consoleButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: color.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: color.withValues(alpha: 0.2)),
          ),
        ),
      ),
    );
  }

  // ───────────────────── SLA bar ─────────────────────

  Widget _buildSLABar(BuildContext context, _SLAData sla) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Text('UPTIME',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 1)),
          const SizedBox(width: 20),
          _buildSLAChip(context, '24h', sla.perfect24h),
          const SizedBox(width: 12),
          _buildSLAChip(context, '7d', sla.perfect7d),
          const SizedBox(width: 12),
          _buildSLAChip(context, '30d', sla.perfect30d),
          const SizedBox(width: 24),
          Container(
              width: 1,
              height: 28,
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.12)),
          const SizedBox(width: 24),
          Text('DOWNTIME',
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5)),
          const SizedBox(width: 12),
          Text(_formatDuration(sla.totalDowntime),
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sla.totalDowntime.inMinutes > 0
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981))),
        ],
      ),
    );
  }

  Widget _buildSLAChip(BuildContext context, String label, double uptime) {
    final color = uptime >= 99.9
        ? const Color(0xFF10B981)
        : (uptime >= 99 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text('${uptime.toStringAsFixed(2)}%',
            style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  // ───────────────────── Scan results ─────────────────────

  Widget _buildScanResultSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('LAST DEEP SCAN REPORT',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900, fontSize: 10, color: Colors.grey, letterSpacing: 1)),
            const Spacer(),
            const Icon(Icons.history, size: 14, color: Colors.grey),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            width: double.infinity,
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
            child: Text(widget.device.lastScanResult!,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: const Color(0xFF34D399), height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ───────────────────── Shared helpers ─────────────────────

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

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  // ───────────────────── Data ─────────────────────

  _SLAData _calculateSLA() {
    final history = widget.device.history;
    if (history.isEmpty) return _SLAData(100, 100, 100, Duration.zero);

    final now = DateTime.now();
    final last24h = history.where((h) => now.difference(h.timestamp).inHours < 24).toList();
    final last7d = history.where((h) => now.difference(h.timestamp).inDays < 7).toList();
    final last30d = history.where((h) => now.difference(h.timestamp).inDays < 30).toList();

    double uptime(List<StatusHistory> h) {
      if (h.isEmpty) return 100.0;
      final online = h.where((e) => e.status == DeviceStatus.online).length;
      return (online / h.length) * 100;
    }

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
      uptime(last24h), uptime(last7d), uptime(last30d),
      totalDowntime,
    );
  }

  /// Computes a human-friendly axis interval (e.g. 0.1, 0.2, 0.5, 1, 2, 5, 10, …).
  double _niceInterval(double maxVal, int targetSteps) {
    if (maxVal <= 0) return 1.0;
    final rough = maxVal / targetSteps;
    final magnitude = pow(10, (log(rough) / ln10).floor()).toDouble();
    final residual = rough / magnitude;
    double nice;
    if (residual <= 1.5) {
      nice = 1;
    } else if (residual <= 3) {
      nice = 2;
    } else if (residual <= 7) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }

  _DeviceStats _calculateStats() {
    if (widget.device.history.isEmpty) return _DeviceStats(0, 0, 0, 0, 0);
    final responded = widget.device.history.where((h) => h.latencyMs != null && h.latencyMs! > 0).toList();
    final uptime = (responded.length / widget.device.history.length) * 100;
    double totalLatency = 0, maxLatency = 0, minLatency = double.infinity, totalLoss = 0;
    for (var h in widget.device.history) {
      totalLoss += h.packetLoss ?? 100;
      if (h.latencyMs != null && h.latencyMs! > 0) {
        totalLatency += h.latencyMs!;
        if (h.latencyMs! > maxLatency) maxLatency = h.latencyMs!;
        if (h.latencyMs! < minLatency) minLatency = h.latencyMs!;
      }
    }
    if (minLatency == double.infinity) minLatency = 0;
    return _DeviceStats(
      uptime,
      responded.isEmpty ? 0 : totalLatency / responded.length,
      maxLatency,
      minLatency,
      totalLoss / widget.device.history.length,
    );
  }
}

class _DeviceStats {
  final double uptime, avgLatency, maxLatency, minLatency, avgLoss;
  _DeviceStats(this.uptime, this.avgLatency, this.maxLatency, this.minLatency, this.avgLoss);
}

class _SLAData {
  final double perfect24h, perfect7d, perfect30d;
  final Duration totalDowntime;
  _SLAData(this.perfect24h, this.perfect7d, this.perfect30d, this.totalDowntime);
}

class _PingResult {
  final int seq;
  final double? latencyMs;
  final DateTime timestamp;
  _PingResult({required this.seq, this.latencyMs, required this.timestamp});
}
