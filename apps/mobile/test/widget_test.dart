import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile/app.dart';

void main() {
  testWidgets('Onboarding is shown on startup', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TerrangoApp()));

    expect(find.text('Terrango - Onboarding'), findsOneWidget);
    expect(find.text('Rychla registrace a start'), findsOneWidget);
  });
}
