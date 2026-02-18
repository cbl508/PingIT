import 'package:flutter_test/flutter_test.dart';
import 'package:pingit/models/device_model.dart';
import 'package:pingit/providers/device_provider.dart';
import 'package:pingit/services/alert_service.dart';
import 'package:pingit/services/email_service.dart';
import 'package:pingit/services/notification_service.dart';
import 'package:pingit/services/ping_service.dart';
import 'package:pingit/services/storage_service.dart';
import 'package:pingit/services/webhook_service.dart';

// Mocks
class MockStorageService extends StorageService {
  List<Device> devices = [];
  List<DeviceGroup> groups = [];
  EmailSettings emailSettings = EmailSettings();
  WebhookSettings webhookSettings = WebhookSettings();
  QuietHoursSettings quietHoursSettings = QuietHoursSettings();

  @override
  Future<List<Device>> loadDevices() async => devices;

  @override
  Future<List<DeviceGroup>> loadGroups() async => groups;

  @override
  Future<EmailSettings> loadEmailSettings() async => emailSettings;

  @override
  Future<WebhookSettings> loadWebhookSettings() async => webhookSettings;

  @override
  Future<QuietHoursSettings> loadQuietHours() async => quietHoursSettings;

  @override
  Future<void> saveDevices(List<Device> devices) async {
    this.devices = devices;
  }

  @override
  Future<void> saveGroups(List<DeviceGroup> groups) async {
    this.groups = groups;
  }

  @override
  Future<void> saveEmailSettings(EmailSettings settings) async {
    emailSettings = settings;
  }

  @override
  Future<void> saveWebhookSettings(WebhookSettings settings) async {
    webhookSettings = settings;
  }

  @override
  Future<void> saveQuietHours(QuietHoursSettings settings) async {
    quietHoursSettings = settings;
  }
}

class MockPingService extends PingService {
  @override
  int get backoffSeconds => 0;

  @override
  Future<void> pingAllDevices(List<Device> devices, {Function(Device, DeviceStatus, DeviceStatus)? onStatusChanged}) async {
    // No-op for testing
  }
}

class MockAlertService extends AlertService {
  @override
  Future<void> playAlert(DeviceStatus status) async {}
}

class MockNotificationService extends NotificationService {
  @override
  Future<void> showStatusChangeNotification(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {}
}

class MockEmailService extends EmailService {
  @override
  void updateSettings(EmailSettings settings) {}
  
  @override
  Future<void> sendAlert(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {}
}

class MockWebhookService extends WebhookService {
  @override
  void updateSettings(WebhookSettings settings) {}

  @override
  Future<void> sendAlert(Device device, DeviceStatus oldStatus, DeviceStatus newStatus) async {}
}

void main() {
  group('DeviceProvider', () {
    late MockStorageService storageService;
    late DeviceProvider provider;

    setUp(() async {
      storageService = MockStorageService();
      // Initialize mocks
      storageService.devices = [];
      storageService.groups = [];

      provider = DeviceProvider(
        storageService: storageService,
        pingService: MockPingService(),
        alertService: MockAlertService(),
        notificationService: MockNotificationService(),
        emailService: MockEmailService(),
        webhookService: MockWebhookService(),
      );
      // Wait for _init to complete (though not awaited in constructor)
      await Future.delayed(Duration.zero);
    });

    test('initial state is correct', () {
      expect(provider.devices, isEmpty);
      expect(provider.groups, isEmpty);
    });

    test('addDevice adds a device and notifies listeners', () async {
      final device = Device(name: 'Test Device', address: '127.0.0.1');
      
      bool notified = false;
      provider.addListener(() {
        notified = true;
      });

      provider.addDevice(device);
      provider.saveAll(immediate: true); // Force save

      expect(provider.devices, contains(device));
      expect(notified, isTrue);
      
      // Wait for async save to complete if needed, but saveAll(immediate: true) awaits _flushPendingSaves?
      // No, saveAll returns void. But _flushPendingSaves is async.
      // So we can't await it easily.
      // But we can check memory state provider.devices.
      // Checking storageService.devices might be flaky without awaiting save.
      // Let's just check memory state which is enough for provider logic.
    });

    test('removeDevice removes a device', () {
      final device = Device(name: 'Test Device', address: '127.0.0.1');
      provider.addDevice(device);
      expect(provider.devices, contains(device));

      provider.removeDevice(device);
      expect(provider.devices, isNot(contains(device)));
    });
  });
}
