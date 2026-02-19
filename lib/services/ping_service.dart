import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dart_ping/dart_ping.dart';
import 'package:http/http.dart' as http;
import 'package:pingit/models/device_model.dart';

class PingService {
  static const int _pingCount = 3;
  static const double _latencyWarningThreshold = 500.0;
  static const double _packetLossWarningThreshold = 10.0;

  // Exponential backoff for repeated poll failures
  int _consecutivePollFailures = 0;
  static const int _maxBackoffSeconds = 300;

  int get backoffSeconds {
    if (_consecutivePollFailures <= 0) return 0;
    final seconds = 1 << _consecutivePollFailures.clamp(0, 8);
    return seconds.clamp(0, _maxBackoffSeconds);
  }

  void recordPollSuccess() => _consecutivePollFailures = 0;
  void recordPollFailure() => _consecutivePollFailures++;

  Future<void> pingDevice(Device device, {
    Function(Device, DeviceStatus, DeviceStatus)? onStatusChanged,
    Function(Device, StatusHistory)? onResult,
  }) async {
    if (device.isPaused) return;
    if (device.isInMaintenance) return;

    final now = DateTime.now();

    if (device.lastPingTime != null) {
      final difference = now.difference(device.lastPingTime!);
      if (difference.inSeconds < device.interval) {
        return;
      }
    }

    final oldStatus = device.status;
    final result = await _performCheck(device);

    // Track consecutive failures (backwards compat)
    if (result.status == DeviceStatus.offline) {
      device.consecutiveFailures++;
    } else {
      device.consecutiveFailures = 0;
    }

    // Record raw check result and metrics
    device.lastLatency = result.latency;
    device.packetLoss = result.packetLoss;
    device.lastResponseCode = result.responseCode;
    device.lastPingTime = now;

    DeviceStatus statusToRecord = result.status;

    // --- Advanced Monitoring Integration ---
    if (statusToRecord == DeviceStatus.online) {
      // 1. Keyword Match (HTTP only)
      if (device.checkType == CheckType.http && device.keyword != null && device.keyword!.isNotEmpty) {
        final matches = await _checkKeywordMatch(device.address, device.keyword!);
        if (!matches) statusToRecord = DeviceStatus.degraded;
      }

      // 2. DNS Check
      if (device.dnsExpectedIp != null && device.dnsExpectedIp!.isNotEmpty) {
        final dnsOk = await _checkDns(device.address, device.dnsExpectedIp!, device.dnsRecordType ?? 'A');
        if (!dnsOk) statusToRecord = DeviceStatus.degraded;
      }

      // 3. SSL Expiry Check (HTTPS only)
      if (device.checkType == CheckType.http && device.address.toLowerCase().startsWith('https')) {
        final expiry = await _checkSslExpiry(device.address);
        if (expiry != null) {
          device.sslExpiryDate = expiry;
          final daysLeft = expiry.difference(DateTime.now()).inDays;
          final threshold = device.sslExpiryWarningDays ?? 14;
          if (daysLeft <= threshold) statusToRecord = DeviceStatus.degraded;
        }
      }
    }

    // Store raw check result in history
    final historyEntry = StatusHistory(
      timestamp: now,
      status: statusToRecord,
      latencyMs: result.latency,
      packetLoss: result.packetLoss,
      responseCode: result.responseCode,
    );
    
    device.history.add(historyEntry);
    onResult?.call(device, historyEntry);

    if (device.history.length > device.maxHistory) {
      device.history.removeRange(0, device.history.length - device.maxHistory);
    }

    // Evaluate effective device status using sliding window over recent history
    final effectiveStatus = _evaluateDeviceStatus(device);
    device.status = effectiveStatus;

    if (effectiveStatus != oldStatus && onStatusChanged != null) {
      onStatusChanged(device, oldStatus, effectiveStatus);
    }
  }

  Future<bool> _checkKeywordMatch(String address, String keyword) async {
    try {
      String url = address;
      if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      return response.body.contains(keyword);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkDns(String host, String expectedIp, String type) async {
    try {
      // Remove scheme/path for lookup
      final cleanHost = host.replaceFirst(RegExp(r'^https?://'), '').split('/').first.split(':').first;
      final results = await InternetAddress.lookup(cleanHost);
      return results.any((addr) => addr.address == expectedIp);
    } catch (_) {
      return false;
    }
  }

  Future<DateTime?> _checkSslExpiry(String address) async {
    SecureSocket? socket;
    try {
      final cleanHost = address.replaceFirst(RegExp(r'^https?://'), '').split('/').first.split(':').first;
      socket = await SecureSocket.connect(cleanHost, 443, timeout: const Duration(seconds: 5));
      final dynamic cert = socket.peerCertificate;
      final DateTime? expiry = cert?.end;
      return expiry;
    } catch (_) {
      return null;
    } finally {
      await socket?.close();
    }
  }

  /// Determines the device's effective status by analysing recent history.
  ///
  /// - **Offline** : last [failureThreshold] raw checks ALL completely failed,
  ///   OR the device has been non-online for [failureThreshold * 3] consecutive
  ///   checks (covers sustained partial-failure / degraded streaks).
  /// - **Degraded** : the sliding window contains any non-online entries
  ///   (flapping, intermittent loss, elevated latency).
  /// - **Online** : entire sliding window is clean.
  DeviceStatus _evaluateDeviceStatus(Device device) {
    final history = device.history;
    if (history.isEmpty) return DeviceStatus.unknown;

    // --- Offline detection ---

    // 1. Consecutive trailing complete failures (raw status == offline)
    int trailingOffline = 0;
    for (int i = history.length - 1; i >= 0; i--) {
      if (history[i].status == DeviceStatus.offline) {
        trailingOffline++;
      } else {
        break;
      }
    }
    if (trailingOffline >= device.failureThreshold) {
      return DeviceStatus.offline;
    }

    // 2. Consecutive trailing non-online entries (offline + degraded).
    //    Escalates to offline after a longer streak — covers the case where
    //    partial responses keep the raw status as "degraded" indefinitely.
    int trailingNonOnline = 0;
    for (int i = history.length - 1; i >= 0; i--) {
      if (history[i].status != DeviceStatus.online) {
        trailingNonOnline++;
      } else {
        break;
      }
    }
    if (trailingNonOnline >= device.failureThreshold * 3) {
      return DeviceStatus.offline;
    }

    // --- Degraded vs Online ---

    final windowSize = max(device.failureThreshold, 5);
    final window = history.length > windowSize
        ? history.sublist(history.length - windowSize)
        : history;

    // Any non-online entry in the window → unstable / flapping → degraded
    final hasIssues = window.any((h) => h.status != DeviceStatus.online);
    if (hasIssues) {
      return DeviceStatus.degraded;
    }

    // Check user-defined thresholds against the latest result
    final latest = history.last;
    if (device.latencyThreshold != null &&
        latest.latencyMs != null &&
        latest.latencyMs! > device.latencyThreshold!) {
      return DeviceStatus.degraded;
    }
    if (device.packetLossThreshold != null &&
        (latest.packetLoss ?? 0) > device.packetLossThreshold!) {
      return DeviceStatus.degraded;
    }

    return DeviceStatus.online;
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
      url = 'http://$url';
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
      int timed = 0;
      double totalLatency = 0;

      // Locale-independent: match lines containing "TTL" (universal across locales)
      // and extract latency from "=Xms" or "<Xms" patterns on the same line.
      final latencyRegex = RegExp(r'[=<]\s*(\d+)\s*ms', caseSensitive: false);
      for (final line in lines) {
        if (line.toUpperCase().contains('TTL')) {
          received++;
          final match = latencyRegex.firstMatch(line);
          if (match != null) {
            timed++;
            totalLatency += double.parse(match.group(1)!);
          }
        }
      }

      if (received > 0) {
        final avgLatency = timed > 0 ? totalLatency / timed : null;
        final loss = ((_pingCount - received) / _pingCount) * 100.0;

        DeviceStatus status = DeviceStatus.online;
        if ((avgLatency != null && avgLatency > _latencyWarningThreshold) || loss > _packetLossWarningThreshold) {
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
        // Only count genuine echo replies (have timing data).
        // ICMP error messages (host unreachable, etc.) have response != null
        // but time == null — these are NOT successful responses.
        if (event.response != null && event.response!.time != null) {
          received++;
          totalLatency += event.response!.time!.inMicroseconds / 1000.0;
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

  static const int _maxConcurrentChecks = 20;

  /// Only pings devices that are due based on their interval.
  /// Limits concurrency to [_maxConcurrentChecks] to avoid resource exhaustion.
  Future<void> pingAllDevices(List<Device> devices, {
    Function(Device, DeviceStatus, DeviceStatus)? onStatusChanged,
    Function(Device, StatusHistory)? onResult,
  }) async {
    final now = DateTime.now();
    final due = devices.where((d) {
      if (d.isPaused) return false;
      if (d.isInMaintenance) return false;
      if (d.lastPingTime == null) return true;
      return now.difference(d.lastPingTime!).inSeconds >= d.interval;
    }).toList();

    if (due.isEmpty) return;
    try {
      // Process in batches to limit concurrent connections
      for (int i = 0; i < due.length; i += _maxConcurrentChecks) {
        final batch = due.sublist(i, (i + _maxConcurrentChecks).clamp(0, due.length));
        await Future.wait(batch.map((device) => pingDevice(
          device, 
          onStatusChanged: onStatusChanged,
          onResult: onResult,
        )));
      }
      recordPollSuccess();
    } catch (e) {
      recordPollFailure();
      rethrow;
    }
  }

  /// Performs a single check for a device without affecting history or alerts.
  Future<({DeviceStatus status, double? latency, double packetLoss, int? responseCode})> performSingleCheck(Device device) async {
    return _performCheck(device);
  }
}
