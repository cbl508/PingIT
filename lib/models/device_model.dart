import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'device_model.g.dart';

enum DeviceStatus {
  online,
  offline,
  degraded,
  unknown,
}

enum DeviceType {
  server,
  database,
  router,
  workstation,
  iot,
  website,
  cloud,
}

enum CheckType {
  icmp,
  tcp,
  http,
}

@JsonSerializable()
class StatusHistory {
  StatusHistory({
    required this.timestamp,
    required this.status,
    this.latencyMs,
    this.packetLoss,
    this.responseCode,
  });

  final DateTime timestamp;
  final DeviceStatus status;
  final double? latencyMs;
  final double? packetLoss;
  final int? responseCode;

  factory StatusHistory.fromJson(Map<String, dynamic> json) => _$StatusHistoryFromJson(json);
  Map<String, dynamic> toJson() => _$StatusHistoryToJson(this);
}

@JsonSerializable()
class DeviceGroup {
  DeviceGroup({
    required this.id,
    required this.name,
    this.isExpanded = true,
  });

  final String id;
  String name;
  bool isExpanded;

  factory DeviceGroup.fromJson(Map<String, dynamic> json) => _$DeviceGroupFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceGroupToJson(this);
}

@JsonSerializable(explicitToJson: true)
class Device {
  Device({
    String? id,
    required this.name,
    required this.address,
    this.groupId,
    this.interval = 10,
    this.tags = const [],
    this.type = DeviceType.server,
    this.checkType = CheckType.icmp,
    this.port,
    this.status = DeviceStatus.unknown,
    this.isPaused = false,
    this.lastLatency,
    this.packetLoss,
    this.lastResponseCode,
    this.failureThreshold = 1,
    this.latencyThreshold,
    this.packetLossThreshold,
    this.consecutiveFailures = 0,
    this.topologyX,
    this.topologyY,
    this.parentId,
    List<StatusHistory>? history,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       history = history ?? [];

  final String id;
  String name;
  String address;
  String? groupId;
  int interval;
  List<String> tags;
  DeviceType type;
  CheckType checkType;
  int? port;
  bool isPaused;
  int failureThreshold;
  double? latencyThreshold;
  double? packetLossThreshold;

  int consecutiveFailures;

  @JsonKey(includeFromJson: false, includeToJson: false)
  DeviceStatus status;

  @JsonKey(includeFromJson: false, includeToJson: false)
  double? lastLatency;

  @JsonKey(includeFromJson: false, includeToJson: false)
  double? packetLoss;

  @JsonKey(includeFromJson: false, includeToJson: false)
  int? lastResponseCode;

  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime? lastPingTime;

  @JsonKey(includeFromJson: false, includeToJson: false)
  String? lastScanResult;

  double? topologyX;
  double? topologyY;
  String? parentId;

  final List<StatusHistory> history;

  // Calculated property: 0.0 to 100.0
  double get stabilityScore {
    if (history.isEmpty) return 100.0;

    // Weight status heavily (offline is bad)
    final onlineCount = history.where((h) => h.status == DeviceStatus.online).length;
    final uptimeScore = (onlineCount / history.length) * 100;

    // Weight packet loss
    double totalLoss = 0;
    for (var h in history) {
      totalLoss += h.packetLoss ?? 0;
    }
    final avgLoss = totalLoss / history.length;
    final lossScore = 100 - avgLoss;

    // Combined score: 70% uptime, 30% packet loss reliability
    return (uptimeScore * 0.7) + (lossScore * 0.3);
  }

  // Helper for UI icons
  IconData get typeIcon {
    if (status == DeviceStatus.degraded) return Icons.warning_amber_rounded;
    switch (type) {
      case DeviceType.server: return Icons.dns;
      case DeviceType.database: return Icons.storage;
      case DeviceType.router: return Icons.router;
      case DeviceType.workstation: return Icons.computer;
      case DeviceType.iot: return Icons.memory;
      case DeviceType.website: return Icons.language;
      case DeviceType.cloud: return Icons.cloud;
    }
  }

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceToJson(this);
}
