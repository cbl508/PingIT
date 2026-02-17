import 'package:flutter_test/flutter_test.dart';
import 'package:pingit/models/device_model.dart';

void main() {
  test('stabilityScore weights uptime and packet loss', () {
    final device = Device(name: 'web-01', address: 'example.com');
    device.history.addAll([
      StatusHistory(
        timestamp: DateTime(2026, 1, 1, 12, 0, 0),
        status: DeviceStatus.online,
        latencyMs: 10,
        packetLoss: 0,
      ),
      StatusHistory(
        timestamp: DateTime(2026, 1, 1, 12, 0, 10),
        status: DeviceStatus.offline,
        latencyMs: null,
        packetLoss: 100,
      ),
    ]);

    expect(device.stabilityScore, closeTo(35.0, 0.001));
  });
}
