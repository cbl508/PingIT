import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pingit/models/device_model.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._();
  factory DatabaseService() => _instance;
  DatabaseService._();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = join(dir.path, 'pingit.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Devices table
    await db.execute('''
      CREATE TABLE devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        group_id TEXT,
        interval INTEGER NOT NULL,
        tags TEXT,
        type TEXT NOT NULL,
        check_type TEXT NOT NULL,
        port INTEGER,
        is_paused INTEGER NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        failure_threshold INTEGER NOT NULL,
        latency_threshold REAL,
        packet_loss_threshold REAL,
        max_history INTEGER NOT NULL,
        maintenance_until TEXT,
        topology_x REAL,
        topology_y REAL,
        parent_id TEXT,
        
        -- Advanced Monitoring Fields
        ssl_expiry_date TEXT,
        ssl_expiry_warning_days INTEGER,
        keyword_match TEXT,
        dns_expected_ip TEXT,
        dns_record_type TEXT,

        -- Integration Fields
        discord_webhook_url TEXT,
        slack_webhook_url TEXT
      )
    ''');

    // Groups table
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_expanded INTEGER NOT NULL
      )
    ''');

    // Logs/History table
    // Using a separate table for history allows for massive scaling
    await db.execute('''
      CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        latency_ms REAL,
        packet_loss REAL,
        response_code INTEGER,
        FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
      )
    ''');
    
    // Index for fast history lookups
    await db.execute('CREATE INDEX idx_history_device_timestamp ON history (device_id, timestamp DESC)');
  }

  // --- Devices ---

  Future<void> saveDevice(Device device) async {
    if (_db == null) await init();
    await _db!.insert(
      'devices',
      _deviceToMap(device),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDevice(String id) async {
    if (_db == null) await init();
    await _db!.delete('devices', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Device>> getAllDevices() async {
    if (_db == null) await init();
    final List<Map<String, dynamic>> maps = await _db!.query('devices');
    
    final devices = <Device>[];
    for (final m in maps) {
      final d = _mapToDevice(m);
      // Load recent history (e.g. last 100) to keep the UI snappy
      d.history.addAll(await getDeviceHistory(d.id, limit: 100));
      
      // Restore runtime status from last history item
      if (d.history.isNotEmpty) {
        final last = d.history.last;
        d.status = last.status;
        d.lastLatency = last.latencyMs;
        d.packetLoss = last.packetLoss;
        d.lastResponseCode = last.responseCode;
      }
      devices.add(d);
    }
    return devices;
  }

  // --- History ---

  Future<void> addHistoryEntry(String deviceId, StatusHistory entry) async {
    if (_db == null) await init();
    await _db!.insert('history', {
      'device_id': deviceId,
      'timestamp': entry.timestamp.toIso8601String(),
      'status': entry.status.name,
      'latency_ms': entry.latencyMs,
      'packet_loss': entry.packetLoss,
      'response_code': entry.responseCode,
    });
  }

  Future<List<StatusHistory>> getDeviceHistory(String deviceId, {int limit = 100, int offset = 0}) async {
    if (_db == null) await init();
    final List<Map<String, dynamic>> maps = await _db!.query(
      'history',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp ASC', // Keep consistent with existing logic (oldest first in list usually, but UI might reverse)
      // Actually, model usually keeps list in append order. 
      // To get "latest", we might query DESC limit X, then reverse back.
      // But standard append list:
    );
    
    // Optimizing: if list is huge, we only fetch what we need.
    // However, the current app architecture expects `device.history` to be a List in memory.
    // For now, we will load "recent" history on app load, and "load more" will fetch from DB.
    
    // For this specific method, let's fetch strictly sorted by time.
    // If limit is small, we probably want the *latest* entries.
    final rows = await _db!.query(
      'history',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => StatusHistory(
      timestamp: DateTime.parse(r['timestamp'] as String),
      status: DeviceStatus.values.firstWhere((e) => e.name == r['status']),
      latencyMs: r['latency_ms'] as double?,
      packetLoss: r['packet_loss'] as double?,
      responseCode: r['response_code'] as int?,
    )).toList().reversed.toList(); // Return in chronological order
  }

  Future<void> pruneHistory(String deviceId, int maxHistory) async {
    if (_db == null) await init();
    // Keep only the latest N entries
    await _db!.execute('''
      DELETE FROM history 
      WHERE device_id = ? AND id NOT IN (
        SELECT id FROM history 
        WHERE device_id = ? 
        ORDER BY timestamp DESC 
        LIMIT ?
      )
    ''', [deviceId, deviceId, maxHistory]);
  }

  // --- Groups ---

  Future<void> saveGroup(DeviceGroup group) async {
    if (_db == null) await init();
    await _db!.insert('groups', {
      'id': group.id,
      'name': group.name,
      'is_expanded': group.isExpanded ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<DeviceGroup>> getAllGroups() async {
    if (_db == null) await init();
    final maps = await _db!.query('groups');
    return maps.map((m) => DeviceGroup(
      id: m['id'] as String,
      name: m['name'] as String,
      isExpanded: (m['is_expanded'] as int) == 1,
    )).toList();
  }

  Future<void> deleteGroup(String id) async {
    if (_db == null) await init();
    await _db!.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  // --- Legacy Migration ---

  Future<bool> hasData() async {
    if (_db == null) await init();
    final count = Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM devices'));
    return (count ?? 0) > 0;
  }

  // --- Serialization Helpers ---

  Map<String, dynamic> _deviceToMap(Device d) {
    return {
      'id': d.id,
      'name': d.name,
      'address': d.address,
      'group_id': d.groupId,
      'interval': d.interval,
      'tags': d.tags.join(','),
      'type': d.type.name,
      'check_type': d.checkType.name,
      'port': d.port,
      'is_paused': d.isPaused ? 1 : 0,
      'is_pinned': d.isPinned ? 1 : 0,
      'failure_threshold': d.failureThreshold,
      'latency_threshold': d.latencyThreshold,
      'packet_loss_threshold': d.packetLossThreshold,
      'max_history': d.maxHistory,
      'maintenance_until': d.maintenanceUntil?.toIso8601String(),
      'topology_x': d.topologyX,
      'topology_y': d.topologyY,
      'parent_id': d.parentId,
      'ssl_expiry_date': d.sslExpiryDate?.toIso8601String(),
      'ssl_expiry_warning_days': d.sslExpiryWarningDays,
      'keyword_match': d.keyword,
      'dns_expected_ip': d.dnsExpectedIp,
      'dns_record_type': d.dnsRecordType,
      'discord_webhook_url': d.discordWebhookUrl,
      'slack_webhook_url': d.slackWebhookUrl,
    };
  }

  Device _mapToDevice(Map<String, dynamic> m) {
    return Device(
      id: m['id'],
      name: m['name'],
      address: m['address'],
      groupId: m['group_id'],
      interval: m['interval'],
      tags: (m['tags'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
      type: DeviceType.values.firstWhere((e) => e.name == m['type']),
      checkType: CheckType.values.firstWhere((e) => e.name == m['check_type']),
      port: m['port'],
      isPaused: (m['is_paused'] as int) == 1,
      isPinned: (m['is_pinned'] as int) == 1,
      failureThreshold: m['failure_threshold'],
      latencyThreshold: m['latency_threshold'],
      packetLossThreshold: m['packet_loss_threshold'],
      maxHistory: m['max_history'],
      maintenanceUntil: m['maintenance_until'] != null ? DateTime.parse(m['maintenance_until']) : null,
      topologyX: m['topology_x'],
      topologyY: m['topology_y'],
      parentId: m['parent_id'],
      sslExpiryDate: m['ssl_expiry_date'] != null ? DateTime.parse(m['ssl_expiry_date']) : null,
      sslExpiryWarningDays: m['ssl_expiry_warning_days'],
      keyword: m['keyword_match'],
      dnsExpectedIp: m['dns_expected_ip'],
      dnsRecordType: m['dns_record_type'],
      discordWebhookUrl: m['discord_webhook_url'],
      slackWebhookUrl: m['slack_webhook_url'],
    );
  }
}
