import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:terrango_mobile/app.dart';
import 'package:terrango_mobile/state/game_session_controller.dart';

void main() {
  testWidgets('shows onboarding on first launch and shell after registration', (WidgetTester tester) async {
    final controller = GameSessionController();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const TerrangoApp(),
      ),
    );

    expect(find.text('Terrango'), findsOneWidget);
    expect(find.text('Start immediately'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'TestCommander');
    await tester.tap(find.text('Start immediately'));
    await tester.pumpAndSettle();

    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Recruit'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
