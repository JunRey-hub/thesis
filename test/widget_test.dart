import 'package:flutter_test/flutter_test.dart';
import 'package:thesis/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Pass showOnboarding: false so the test doesn't try to load SharedPreferences
    await tester.pumpWidget(const MyApp(showOnboarding: false));
  });
}