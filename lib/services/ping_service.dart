import 'dart:async';
import 'dart:io';

import 'package:dart_ping/dart_ping.dart';
import 'package:http/http.dart' as http;
import 'package:pingit/models/device_model.dart';

class PingService {
  static const int _pingCount = 3;
  static const double _latencyWarningThreshold = 500.0;
  static const double _packetLossWarningThreshold = 10.0;
  static const int _maxHistory = 2000;

  Future<void> pingDevice(Device device, {Function(Device, DeviceStatus, DeviceStatus)? onStatusChanged}) async {
    if (device.isPaused) return;

    final now = DateTime.now();

    if (device.lastPingTime != null) {
      final difference = now.difference(device.lastPingTime!);
      if (difference.inSeconds < device.interval) {
        return;
      }
    }

    final oldStatus = device.status;

    final result = await _performCheck(device);

    // Track consecutive failures for alert thresholds
    if (result.status == DeviceStatus.offline) {
      device.consecutiveFailures++;
    } else {
      device.consecutiveFailures = 0;
    }

    // Apply failure threshold: only transition to offline after N consecutive failures
    DeviceStatus effectiveStatus = result.status;
    if (result.status == DeviceStatus.offline &&
        device.consecutiveFailures < device.failureThreshold &&
        oldStatus != DeviceStatus.unknown) {
      effectiveStatus = oldStatus;
    }

    // Check user-defined thresholds for degraded detection
    if (effectiveStatus == DeviceStatus.online) {
      if (device.latencyThreshold != null &&
          result.latency != null &&
          result.latency! > device.latencyThreshold!) {
        effectiveStatus = DeviceStatus.degraded;
      }
      if (device.packetLossThreshold != null &&
          result.packetLoss > device.packetLossThreshold!) {
        effectiveStatus = DeviceStatus.degraded;
      }
    }

    device.status = effectiveStatus;
    device.lastLatency = result.latency;
    device.packetLoss = result.packetLoss;
    device.lastResponseCode = result.responseCode;
    device.lastPingTime = now;

    device.history.add(StatusHistory(
      timestamp: now,
      status: effectiveStatus,
      latencyMs: result.latency,
      packetLoss: result.packetLoss,
      responseCode: result.responseCode,
    ));

    if (device.history.length > _maxHistory) {
      device.history.removeAt(0);
    }

    if (effectiveStatus != oldStatus && onStatusChanged != null) {
      onStatusChanged(device, oldStatus, effectiveStatus);
    }
  }

  Future<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})> _performCheck(Device device) async {
    switch (device.checkType) {
      case CheckType.tcp:
        return _getTcpResult(device.address, device.port ?? 80);
      case CheckType.http:
        return _getHttpResult(device.address);
      case CheckType.icmp:
        return _getIcmpResult(device.address);
    }
  }

  Future<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})> _getHttpResult(String address) async {
    String url = address;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds.toDouble();
      final isSuccess = response.statusCode >= 200 && response.statusCode < 400;

      DeviceStatus status = isSuccess ? DeviceStatus.online : DeviceStatus.offline;
      if (isSuccess && latency > _latencyWarningThreshold) {
        status = DeviceStatus.degraded;
      }

      return (
        status: status,
        latency: latency,
        packetLoss: isSuccess ? 0.0 : 100.0,
        responseCode: response.statusCode,
      );
    } on TimeoutException {
      stopwatch.stop();
      return (status: DeviceStatus.offline, latency: null, packetLoss: 100.0, responseCode: null);
    } catch (e) {
      stopwatch.stop();
      return (status: DeviceStatus.offline, latency: null, packetLoss: 100.0, responseCode: null);
    }
  }

  Future<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})> _getTcpResult(String address, int port) async {
    int successCount = 0;
    double totalLatency = 0;

    for (int i = 0; i < _pingCount; i++) {
      final stopwatch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(address, port, timeout: const Duration(seconds: 2));
        stopwatch.stop();
        socket.destroy();
        successCount++;
        totalLatency += stopwatch.elapsedMilliseconds;
      } catch (e) {
        stopwatch.stop();
      }
    }

    if (successCount > 0) {
      final avgLatency = totalLatency / successCount;
      final loss = ((_pingCount - successCount) / _pingCount) * 100.0;

      DeviceStatus status = DeviceStatus.online;
      if (avgLatency > _latencyWarningThreshold || loss > _packetLossWarningThreshold) {
        status = DeviceStatus.degraded;
      }

      return (
        status: status,
        latency: avgLatency,
        packetLoss: loss,
        responseCode: null,
      );
    } else {
      return (status: DeviceStatus.offline, latency: null, packetLoss: 100.0, responseCode: null);
    }
  }

  Future<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})> _getIcmpResult(String address) async {
    if (Platform.isWindows) {
      return _getIcmpResultWindows(address);
    }
    return _getIcmpResultNative(address);
  }

  /// Windows ICMP via ping.exe — locale-independent parsing.
  Future<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})> _getIcmpResultWindows(String address) async {
    try {
      final result = await Process.run(
        'ping', ['-n', '$_pingCount', '-w', '2000', address],
      ).timeout(const Duration(seconds: 15));

      final output = result.stdout as String;
      final lines = output.split('\n');

      int received = 0;
      double totalLatency = 0;

      // Locale-independent: match lines containing "TTL" (universal across locales)
      // and extract latency from "=Xms" or "<Xms" patterns on the same line.
      final latencyRegex = RegExp(r'[=<]\s*(\d+)\s*ms', caseSensitive: false);
      for (final line in lines) {
        if (line.toUpperCase().contains('TTL')) {
          received++;
          final match = latencyRegex.firstMatch(line);
          if (match != null) {
            totalLatency += double.parse(match.group(1)!);
          }
        }
      }

      if (received > 0) {
        final avgLatency = totalLatency / received;
        final loss = ((_pingCount - received) / _pingCount) * 100.0;

        DeviceStatus status = DeviceStatus.online;
        if (avgLatency > _latencyWarningThreshold || loss > _packetLossWarningThreshold) {
          status = DeviceStatus.degraded;
        }

        return (status: status, latency: avgLatency, packetLoss: loss, responseCode: null);
      }

      return (status: DeviceStatus.offline, latency: null, packetLoss: 100.0, responseCode: null);
    } catch (e) {
      return (status: DeviceStatus.offline, latency: null, packetLoss: 100.0, responseCode: null);
    }
  }

  /// Native ICMP via dart_ping (Linux/macOS) with proper cleanup.
  Future<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})> _getIcmpResultNative(String address) async {
    final completer = Completer<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})>();
    final ping = Ping(address, count: _pingCount, timeout: 2);

    int received = 0;
    double totalLatency = 0;

    // Guard timer: ensures we always complete even if the stream hangs.
    final guard = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        ping.stop();
        completer.complete((status: DeviceStatus.offline, latency: null, packetLoss: 100.0, responseCode: null));
      }
    });

    final sub = ping.stream.listen(
      (event) {
        if (event.response != null) {
          received++;
          if (event.response!.time != null) {
            totalLatency += event.response!.time!.inMicroseconds / 1000.0;
          }
        }
      },
      onDone: () {
        guard.cancel();
        if (!completer.isCompleted) {
          if (received > 0) {
            final avgLatency = totalLatency / received;
            final loss = ((_pingCount - received) / _pingCount) * 100.0;

            DeviceStatus status = DeviceStatus.online;
            if (avgLatency > _latencyWarningThreshold || loss > _packetLossWarningThreshold) {
              status = DeviceStatus.degraded;
            }

            completer.complete((
              status: status,
              latency: avgLatency,
              packetLoss: loss,
              responseCode: null,
            ));
          } else {
            completer.complete((
              status: DeviceStatus.offline,
              latency: null,
              packetLoss: 100.0,
              responseCode: null,
            ));
          }
        }
      },
      onError: (e) {
        guard.cancel();
        if (!completer.isCompleted) {
          completer.complete((status: DeviceStatus.offline, latency: null, packetLoss: 100.0, responseCode: null));
        }
      },
    );

    // When the guard fires, the subscription gets cancelled after ping.stop().
    completer.future.then((_) => sub.cancel());

    return completer.future;
  }

  /// Only pings devices that are due based on their interval.
  Future<void> pingAllDevices(List<Device> devices, {Function(Device, DeviceStatus, DeviceStatus)? onStatusChanged}) async {
    final now = DateTime.now();
    final due = devices.where((d) {
      if (d.isPaused) return false;
      if (d.lastPingTime == null) return true;
      return now.difference(d.lastPingTime!).inSeconds >= d.interval;
    }).toList();

    if (due.isEmpty) return;
    await Future.wait(due.map((device) => pingDevice(device, onStatusChanged: onStatusChanged)));
  }
}
