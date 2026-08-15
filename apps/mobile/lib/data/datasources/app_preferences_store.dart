import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppPreferencesStore {
  AppPreferencesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const onboardingCompletedKey = 'terrango.pref.onboarding_completed';
  static const wakeLockEnabledKey = 'terrango.pref.wake_lock_enabled';
  static const backgroundTrackingEnabledKey =
      'terrango.pref.background_tracking_enabled';

  final FlutterSecureStorage _storage;

  Future<bool> readBool(String key, {bool fallback = false}) async {
    final value = (await _storage.read(key: key) ?? '').trim().toLowerCase();
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };
  }

  Future<void> writeBool(String key, bool value) async {
    await _storage.write(key: key, value: value.toString());
  }
}

