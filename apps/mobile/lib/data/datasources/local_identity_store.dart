import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalIdentityStore {
  LocalIdentityStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _registrationTokenKey = 'terrango.local.registration_token';

  final FlutterSecureStorage _storage;

  Future<String> loadOrCreateRegistrationToken({required String nickname}) async {
    final existing = (await _storage.read(key: _registrationTokenKey) ?? '').trim();
    if (existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final nicknameFragment = nickname.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final token = [
      'mobile',
      if (nicknameFragment.isNotEmpty) nicknameFragment,
      base64UrlEncode(bytes).replaceAll('=', ''),
      DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
    ].join('-');

    await _storage.write(key: _registrationTokenKey, value: token);
    return token;
  }
}

