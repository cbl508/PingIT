// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StatusHistory _$StatusHistoryFromJson(Map<String, dynamic> json) =>
    StatusHistory(
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: $enumDecode(_$DeviceStatusEnumMap, json['status']),
      latencyMs: (json['latencyMs'] as num?)?.toDouble(),
      packetLoss: (json['packetLoss'] as num?)?.toDouble(),
      responseCode: (json['responseCode'] as num?)?.toInt(),
    );

Map<String, dynamic> _$StatusHistoryToJson(StatusHistory instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp.toIso8601String(),
      'status': _$DeviceStatusEnumMap[instance.status]!,
      'latencyMs': instance.latencyMs,
      'packetLoss': instance.packetLoss,
      'responseCode': instance.responseCode,
    };

const _$DeviceStatusEnumMap = {
  DeviceStatus.online: 'online',
  DeviceStatus.offline: 'offline',
  DeviceStatus.degraded: 'degraded',
  DeviceStatus.unknown: 'unknown',
};

DeviceGroup _$DeviceGroupFromJson(Map<String, dynamic> json) => DeviceGroup(
  id: json['id'] as String,
  name: json['name'] as String,
  isExpanded: json['isExpanded'] as bool? ?? true,
);

Map<String, dynamic> _$DeviceGroupToJson(DeviceGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'isExpanded': instance.isExpanded,
    };

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  id: json['id'] as String?,
  name: json['name'] as String,
  address: json['address'] as String,
  groupId: json['groupId'] as String?,
  interval: (json['interval'] as num?)?.toInt() ?? 10,
  tags:
      (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  type:
      $enumDecodeNullable(_$DeviceTypeEnumMap, json['type']) ??
      DeviceType.server,
  checkType:
      $enumDecodeNullable(_$CheckTypeEnumMap, json['checkType']) ??
      CheckType.icmp,
  port: (json['port'] as num?)?.toInt(),
  isPaused: json['isPaused'] as bool? ?? false,
  topologyX: (json['topologyX'] as num?)?.toDouble(),
  topologyY: (json['topologyY'] as num?)?.toDouble(),
  parentId: json['parentId'] as String?,
  history: (json['history'] as List<dynamic>?)
      ?.map((e) => StatusHistory.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'address': instance.address,
  'groupId': instance.groupId,
  'interval': instance.interval,
  'tags': instance.tags,
  'type': _$DeviceTypeEnumMap[instance.type]!,
  'checkType': _$CheckTypeEnumMap[instance.checkType]!,
  'port': instance.port,
  'isPaused': instance.isPaused,
  'topologyX': instance.topologyX,
  'topologyY': instance.topologyY,
  'parentId': instance.parentId,
  'history': instance.history.map((e) => e.toJson()).toList(),
};

const _$DeviceTypeEnumMap = {
  DeviceType.server: 'server',
  DeviceType.database: 'database',
  DeviceType.router: 'router',
  DeviceType.workstation: 'workstation',
  DeviceType.iot: 'iot',
  DeviceType.website: 'website',
  DeviceType.cloud: 'cloud',
};

const _$CheckTypeEnumMap = {
  CheckType.icmp: 'icmp',
  CheckType.tcp: 'tcp',
  CheckType.http: 'http',
};
