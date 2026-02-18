import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/providers/device_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeviceProvider>();
    final devices = provider.devices;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dashboard_customize_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Dashboard Empty', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Add nodes to see infrastructure health', style: GoogleFonts.inter(color: Colors.grey)),
          ],
        ),
      );
    }

    final online = devices.where((d) => d.status == DeviceStatus.online && !d.isPaused).length;
    final offline = devices.where((d) => d.status == DeviceStatus.offline && !d.isPaused).length;
    final degraded = devices.where((d) => d.status == DeviceStatus.degraded && !d.isPaused).length;
    final paused = devices.where((d) => d.isPaused).length;
    final total = devices.length;

    final topLatency = devices
        .where((d) => !d.isPaused && d.lastLatency != null)
        .toList()
      ..sort((a, b) => (b.lastLatency ?? 0).compareTo(a.lastLatency ?? 0));
    final top5 = topLatency.take(5).toList();

    final allEvents = devices.expand((d) => d.history.map((h) => (d, h))).toList()
      ..sort((a, b) => b.$2.timestamp.compareTo(a.$2.timestamp));
    final recentEvents = allEvents.take(10).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Oversight Dashboard',
              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            const SizedBox(height: 24),
            
            // --- ROW 1: GAUGES ---
            _buildSectionCard(
              context,
              title: 'INFRASTRUCTURE HEALTH',
              child: Row(
                children: [
                  _buildPieChart(context, online, offline, degraded, paused, total),
                  const SizedBox(width: 40),
                  Expanded(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildHUDItem(context, 'ACTIVE', '$online', const Color(0xFF10B981), Icons.check_circle_outline),
                        _buildHUDItem(context, 'CRITICAL', '$offline', const Color(0xFFEF4444), Icons.error_outline),
                        _buildHUDItem(context, 'DEGRADED', '$degraded', const Color(0xFFF59E0B), Icons.warning_amber_rounded),
                        _buildHUDItem(context, 'PAUSED', '$paused', const Color(0xFF94A3B8), Icons.pause_circle_outline),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // --- ROW 2: LATENCY & EVENTS ---
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return isWide 
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildLatencyWidget(context, top5)),
                        const SizedBox(width: 24),
                        Expanded(flex: 3, child: _buildRecentEventsWidget(context, recentEvents)),
                      ],
                    )
                  : Column(
                      children: [
                        _buildLatencyWidget(context, top5),
                        const SizedBox(height: 24),
                        _buildRecentEventsWidget(context, recentEvents),
                      ],
                    );
              },
            ),
            
            const SizedBox(height: 24),
            
            // --- ROW 3: PINNED NODES ---
            _buildPinnedGrid(context, devices.where((d) => d.isPinned).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required String title, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildPieChart(BuildContext context, int online, int offline, int degraded, int paused, int total) {
    return SizedBox(
      width: 160,
      height: 160,
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
                    _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              sectionsSpace: 4,
              centerSpaceRadius: 50,
              sections: [
                _buildPieSection(0, online.toDouble(), const Color(0xFF10B981), total),
                _buildPieSection(1, offline.toDouble(), const Color(0xFFEF4444), total),
                _buildPieSection(2, degraded.toDouble(), const Color(0xFFF59E0B), total),
                _buildPieSection(3, paused.toDouble(), const Color(0xFF94A3B8), total),
              ],
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$total', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold)),
                Text('NODES', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PieChartSectionData _buildPieSection(int index, double value, Color color, int total) {
    final isTouched = index == _touchedIndex;
    final radius = isTouched ? 25.0 : 20.0;
    return PieChartSectionData(
      color: color,
      value: value,
      title: '',
      radius: radius,
      showTitle: false,
    );
  }

  Widget _buildHUDItem(BuildContext context, String label, String value, Color color, IconData icon) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildLatencyWidget(BuildContext context, List<Device> top5) {
    return _buildSectionCard(
      context,
      title: 'TOP LATENCY (ms)',
      child: Column(
        children: top5.isEmpty 
          ? [const Center(child: Text('No telemetry data available'))]
          : top5.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(d.typeIcon, size: 16, color: Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(d.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13))),
                  Text('${d.lastLatency?.toStringAsFixed(1)}', style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
            )).toList(),
      ),
    );
  }

  Widget _buildRecentEventsWidget(BuildContext context, List<(Device, StatusHistory)> events) {
    return _buildSectionCard(
      context,
      title: 'RECENT NETWORK EVENTS',
      child: Column(
        children: events.isEmpty
          ? [const Center(child: Text('No recent events recorded'))]
          : events.map((item) {
              final d = item.$1;
              final h = item.$2;
              final color = h.status == DeviceStatus.online ? Colors.green : (h.status == DeviceStatus.offline ? Colors.red : Colors.orange);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(h.status.name.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Text(DateFormat('HH:mm:ss').format(h.timestamp), style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildPinnedGrid(BuildContext context, List<Device> pinned) {
    if (pinned.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PINNED NODES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisExtent: 100,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: pinned.length,
          itemBuilder: (context, index) => _buildPinnedCard(context, pinned[index]),
        ),
      ],
    );
  }

  Widget _buildPinnedCard(BuildContext context, Device d) {
    final color = d.status == DeviceStatus.online ? Colors.green : (d.status == DeviceStatus.offline ? Colors.red : Colors.orange);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(d.typeIcon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                Text('${d.lastLatency?.toStringAsFixed(1) ?? "--"} ms', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
