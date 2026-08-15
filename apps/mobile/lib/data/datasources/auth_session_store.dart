import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/auth_session.dart';

class AuthSessionStore {
  AuthSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'terrango.auth.token';
  static const _userIdKey = 'terrango.auth.user_id';

  final FlutterSecureStorage _storage;

  Future<AuthSession?> load() async {
    final token = await _storage.read(key: _tokenKey) ?? '';
    final userId = await _storage.read(key: _userIdKey) ?? '';

    if (token.isEmpty || userId.isEmpty) {
      return null;
    }

    return AuthSession(userId: userId, token: token);
  }

  Future<void> save(AuthSession session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _userIdKey, value: session.userId);
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
  }
}
