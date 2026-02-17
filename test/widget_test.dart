import 'package:flutter_test/flutter_test.dart';
import 'package:pingit/main.dart';

void main() {
  testWidgets('app renders dashboard shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('PingIT Overview'), findsOneWidget);
  });
}
