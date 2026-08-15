import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mobile/app.dart';
import 'package:mobile/data/datasources/app_preferences_store.dart';
import 'package:mobile/data/datasources/auth_session_store.dart';
import 'package:mobile/domain/entities/auth_session.dart';
import 'package:mobile/presentation/providers/app_providers.dart';

void main() {
  testWidgets('Onboarding is shown on startup', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStore()),
          appPreferencesStoreProvider.overrideWithValue(_FakeAppPreferencesStore()),
        ],
        child: const TerrangoApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to Terrango'), findsOneWidget);
    expect(find.text('Quick registration and start'), findsOneWidget);
  });
}

class _FakeAuthSessionStore extends AuthSessionStore {
  @override
  Future<AuthSession?> load() async => null;

  @override
  Future<void> save(AuthSession session) async {}

  @override
  Future<void> clear() async {}
}

class _FakeAppPreferencesStore extends AppPreferencesStore {
  final Map<String, bool> _values = <String, bool>{};

  @override
  Future<bool> readBool(String key, {bool fallback = false}) async {
    return _values[key] ?? fallback;
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value;
  }
}

