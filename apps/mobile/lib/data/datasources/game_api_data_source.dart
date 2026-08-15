import 'package:dio/dio.dart';

import '../../domain/entities/army_overview.dart';

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

  Future<void> occupyHex({
    required String h3Index,
    required double latitude,
    required double longitude,
  }) async {
    await _dio.post(
      '/territory/occupy',
      data: {
        'h3Index': h3Index,
        'latitude': latitude,
        'longitude': longitude,
        'garrisonComposition': [
          {
            'type': 'WARRIOR',
            'rarity': 'STANDARD',
            'skill': null,
            'count': 1,
            'totalBs': 100,
          },
        ],
        'territoryName': 'New Outpost',
      },
      options: _options,
    );
  }

  Future<Map<String, dynamic>> getHexDetail(String h3Index) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/hex/$h3Index',
      options: _options,
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<void> setTerritoryCenter({
    required String territoryId,
    required String h3Index,
  }) async {
    await _dio.patch(
      '/territory/$territoryId/center',
      data: {'h3Index': h3Index},
      options: _options,
    );
  }

  Future<ArmyOverview> getBarracksOverview() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/barracks',
      options: _options,
    );

    final data = response.data ?? <String, dynamic>{};
    final reserves = (data['reserves'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    var reserveBs = 0;
    var reserveCount = 0;
    var warriorCount = 0;
    var supportCount = 0;

    for (final bucket in reserves) {
      reserveBs += (bucket['totalBs'] as num?)?.toInt() ?? 0;
      final count = (bucket['count'] as num?)?.toInt() ?? 0;
      reserveCount += count;
      final type = (bucket['type'] as String? ?? '').toUpperCase();
      if (type == 'WARRIOR') {
        warriorCount += count;
      } else if (type == 'SUPPORT') {
        supportCount += count;
      }
    }

    return ArmyOverview(
      reserveBs: reserveBs,
      reserveCount: reserveCount,
      warriorCount: warriorCount,
      supportCount: supportCount,
    );
  }
}

