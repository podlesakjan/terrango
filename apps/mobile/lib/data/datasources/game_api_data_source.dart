import 'package:dio/dio.dart';

import '../../domain/entities/army_overview.dart';
import '../../domain/entities/auth_session.dart';

class GameApiDataSource {
  GameApiDataSource({
    required String baseUrl,
    this.bearerToken,
  }) : _dio = Dio(BaseOptions(baseUrl: baseUrl));

  final Dio _dio;
  final String? bearerToken;

  Options get _options {
    if (bearerToken == null || bearerToken!.isEmpty) {
      return Options();
    }
    return Options(headers: {'Authorization': 'Bearer $bearerToken'});
  }

  Future<AuthSession> register({
    required String nickname,
    required String idToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/register',
      data: {
        'nickname': nickname,
        'idToken': idToken,
      },
    );

    final data = response.data ?? <String, dynamic>{};
    final userId = (data['userId'] as String?)?.trim() ?? '';
    final token = (data['token'] as String?)?.trim() ?? '';
    if (userId.isEmpty || token.isEmpty) {
      throw const FormatException('Invalid server response during registration.');
    }

    return AuthSession(userId: userId, token: token);
  }

  Future<void> establishTerritory({
    required String h3Index,
    required String name,
  }) async {
    await _dio.post(
      'territory/establish',
      data: {
        'h3Index': h3Index,
        'name': name,
      },
      options: _options,
    );
  }

  Future<void> occupyHex({
    required String h3Index,
    required double latitude,
    required double longitude,
    required List<Map<String, dynamic>> garrisonComposition,
    String? territoryName,
  }) async {
    await _dio.post(
      'territory/occupy',
      data: {
        'h3Index': h3Index,
        'latitude': latitude,
        'longitude': longitude,
        'garrisonComposition': garrisonComposition,
        if (territoryName != null && territoryName.trim().isNotEmpty)
          'territoryName': territoryName.trim(),
      },
      options: _options,
    );
  }

  Future<Map<String, dynamic>> getHexDetail(String h3Index) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'hex/$h3Index',
      options: _options,
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> setTerritoryCenter({
    required String territoryId,
    required String h3Index,
  }) async {
    await _dio.patch(
      'territory/$territoryId/center',
      data: {'h3Index': h3Index},
      options: _options,
    );
  }

  Future<Map<String, dynamic>> getTerritoryList() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'territory/list',
      options: _options,
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> renameTerritory({
    required String territoryId,
    required String name,
  }) async {
    await _dio.patch(
      'territory/$territoryId/rename',
      data: {'name': name},
      options: _options,
    );
  }

  Future<List<Map<String, dynamic>>> getBattleLogs() async {
    final response = await _dio.get<List<dynamic>>(
      'battle-logs',
      options: _options,
    );

    return (response.data ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'profile',
      options: _options,
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> changeNickname({
    required String nickname,
  }) async {
    await _dio.patch(
      'profile/nickname',
      data: {'nickname': nickname},
      options: _options,
    );
  }

  Future<ArmyOverview> getBarracksOverview() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'barracks',
      options: _options,
    );

    return ArmyOverview.fromServer(response.data ?? <String, dynamic>{});
  }
}
