import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/main.dart';

void main() {
  testWidgets('EdhiConnectApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EdhiConnectApp());
    await tester.pumpAndSettle();

    expect(find.text('CNIC or staff email'), findsOneWidget);
    expect(find.text('DEMO FAST ACCESS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
