import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/providers/device_provider.dart';

class TopologyScreen extends StatefulWidget {
  const TopologyScreen({super.key});

  @override
  State<TopologyScreen> createState() => _TopologyScreenState();
}

class _TopologyScreenState extends State<TopologyScreen>
    with SingleTickerProviderStateMixin {
  Device? _connectingSource;
  final ValueNotifier<Offset> _mouseNotifier = ValueNotifier(Offset.zero);
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _mouseNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch devices directly from provider
    final devices = context.watch<DeviceProvider>().devices;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Network Topology',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Drag to position \u2022 Click to connect \u2022 Right-click to clear',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
      body: MouseRegion(
        onHover: (e) {
          _mouseNotifier.value = e.localPosition;
        },
        child: Stack(
          children: [
            ValueListenableBuilder<Offset>(
              valueListenable: _mouseNotifier,
              builder: (context, mousePos, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: TopologyPainter(
                    devices: devices,
                    connectingSource: _connectingSource,
                    mousePos: mousePos,
                    isDark: isDark,
                    animation: _animationController,
                  ),
                );
              },
            ),
            ...devices.map((Device device) => _buildDraggableNode(device, devices)),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableNode(Device device, List<Device> allDevices) {
    if (device.topologyX == null) {
      final index = allDevices.indexOf(device);
      device.topologyX = 100.0 + (index % 5) * 150.0;
      device.topologyY = 100.0 + (index ~/ 5) * 150.0;
    }

    final isOnline = device.status == DeviceStatus.online && !device.isPaused;
    final statusColor = device.isPaused
        ? const Color(0xFF94A3B8)
        : (isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444));

    return Positioned(
      left: device.topologyX,
      top: device.topologyY,
      child: Draggable(
        feedback: _buildNodeContent(device, statusColor, true),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: _buildNodeContent(device, statusColor, false),
        ),
        onDragEnd: (details) {
          setState(() {
            final box = context.findRenderObject() as RenderBox;
            final localPos = box.globalToLocal(details.offset);
            device.topologyX = localPos.dx.clamp(0, box.size.width - 120);
            device.topologyY = localPos.dy.clamp(0, box.size.height - 80);
          });
          // Save directly via provider
          context.read<DeviceProvider>().saveAll();
        },
        child: GestureDetector(
          onTap: () {
            setState(() {
              if (_connectingSource == null) {
                _connectingSource = device;
              } else if (_connectingSource == device) {
                _connectingSource = null;
              } else {
                device.parentId = _connectingSource!.id;
                _connectingSource = null;
                context.read<DeviceProvider>().saveAll();
              }
            });
          },
          onSecondaryTap: () {
            setState(() {
              device.parentId = null;
              _connectingSource = null;
            });
            context.read<DeviceProvider>().saveAll();
          },
          child: _buildNodeContent(device, statusColor, false),
        ),
      ),
    );
  }

  Widget _buildNodeContent(Device device, Color statusColor, bool isDragging) {
    final isSelected = _connectingSource == device;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            if (isSelected)
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(device.typeIcon, size: 20, color: statusColor),
            ),
            const SizedBox(height: 8),
            Text(
              device.name,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(
              device.address,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class TopologyPainter extends CustomPainter {
  final List<Device> devices;
  final Device? connectingSource;
  final Offset mousePos;
  final bool isDark;
  final Animation<double> animation;

  TopologyPainter({
    required this.devices,
    required this.connectingSource,
    required this.mousePos,
    required this.isDark,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final packetPaint = Paint()..style = PaintingStyle.fill;

    for (var device in devices) {
      if (device.parentId != null && device.topologyX != null) {
        final parentMatches = devices.where((d) => d.id == device.parentId);
        if (parentMatches.isEmpty) continue;
        final parent = parentMatches.first;

        if (parent.topologyX != null) {
          final isParentDown = parent.status == DeviceStatus.offline && !parent.isPaused;
          final isDeviceDown = device.status == DeviceStatus.offline && !device.isPaused;

          paint.color = isParentDown
              ? Colors.red.withValues(alpha: 0.5)
              : (isDark ? Colors.white24 : Colors.black12);

          final start = Offset(parent.topologyX! + 60, parent.topologyY! + 40);
          final end = Offset(device.topologyX! + 60, device.topologyY! + 40);

          final path = _drawConnection(canvas, start, end, paint);

          if (!isParentDown && !isDeviceDown && !device.isPaused && !parent.isPaused) {
            _drawPackets(canvas, path, packetPaint, device);
          }
        }
      }
    }

    if (connectingSource != null) {
      paint.color = Colors.blue.withValues(alpha: 0.5);
      final start = Offset(
        connectingSource!.topologyX! + 60,
        connectingSource!.topologyY! + 40,
      );
      _drawConnection(canvas, start, mousePos, paint);
    }
  }

  void _drawPackets(Canvas canvas, Path path, Paint paint, Device device) {
    final latency = device.lastLatency ?? 50.0;
    final speedMultiplier = (latency / 100.0).clamp(0.5, 4.0);

    final metrics = path.computeMetrics();
    for (var metric in metrics) {
      final totalLength = metric.length;

      for (int i = 0; i < 3; i++) {
        final baseValue = (animation.value + (i / 3)) % 1.0;
        final offsetValue = (baseValue / speedMultiplier) % 1.0;

        final pos = metric.getTangentForOffset(totalLength * offsetValue);

        if (pos != null) {
          paint.color = Colors.blue.withValues(alpha: 0.9);
          canvas.drawCircle(pos.position, 3, paint);

          paint.color = Colors.blue.withValues(alpha: 0.3);
          canvas.drawCircle(pos.position, 7, paint);

          paint.color = Colors.blue.withValues(alpha: 0.1);
          canvas.drawCircle(pos.position, 12, paint);
        }
      }
    }
  }

  Path _drawConnection(Canvas canvas, Offset start, Offset end, Paint paint) {
    final path = Path();
    path.moveTo(start.dx, start.dy);
    final controlPoint1 = Offset(start.dx, (start.dy + end.dy) / 2);
    final controlPoint2 = Offset(end.dx, (start.dy + end.dy) / 2);
    path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
    return path;
  }

  @override
  bool shouldRepaint(covariant TopologyPainter oldDelegate) {
    return devices != oldDelegate.devices ||
        connectingSource != oldDelegate.connectingSource ||
        mousePos != oldDelegate.mousePos ||
        isDark != oldDelegate.isDark;
  }
}
