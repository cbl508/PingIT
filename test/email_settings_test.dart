import 'package:flutter_test/flutter_test.dart';
import 'package:pingit/services/email_service.dart';

void main() {
  test('toJson omits password and copyWith updates values', () {
    final settings = EmailSettings(
      smtpServer: 'smtp.example.com',
      port: 587,
      username: 'ops@example.com',
      password: 'secret',
      recipientEmail: 'alerts@example.com',
      isEnabled: true,
    );

    final json = settings.toJson();
    expect(json.containsKey('password'), isFalse);

    final updated = settings.copyWith(port: 465, password: 'new-secret');
    expect(updated.port, 465);
    expect(updated.password, 'new-secret');
    expect(updated.smtpServer, 'smtp.example.com');
  });
}
