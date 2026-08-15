import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/datasources/game_api_data_source.dart';
import '../../data/datasources/game_socket_data_source.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/entities/army_overview.dart';
import '../../domain/entities/hex_tile.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/usecases/get_visible_hexes_use_case.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final mapRepositoryProvider = Provider<MapRepository>((ref) {
  return MapRepositoryImpl();
});

final gameApiDataSourceProvider = Provider<GameApiDataSource>((ref) {
  final config = ref.watch(appConfigProvider);
  return GameApiDataSource(
    baseUrl: config.apiBaseUrl,
    bearerToken: config.apiBearerToken,
  );
});

final gameSocketDataSourceProvider = Provider<GameSocketDataSource>((ref) {
  final config = ref.watch(appConfigProvider);
  final socket = GameSocketDataSource(config.websocketUrl);
  ref.onDispose(socket.close);
  return socket;
});

final getVisibleHexesUseCaseProvider = Provider<GetVisibleHexesUseCase>((ref) {
  final repository = ref.watch(mapRepositoryProvider);
  return GetVisibleHexesUseCase(repository);
});

final visibleHexesProvider = FutureProvider<List<HexTile>>((ref) {
  final useCase = ref.watch(getVisibleHexesUseCaseProvider);
  return useCase();
});

final nicknameProvider = StateProvider<String>((ref) => '');

final armyOverviewProvider =
    StateNotifierProvider<ArmyOverviewNotifier, AsyncValue<ArmyOverview>>((
      ref,
    ) {
      return ArmyOverviewNotifier(
        api: ref.watch(gameApiDataSourceProvider),
        socket: ref.watch(gameSocketDataSourceProvider),
      );
    });

class ArmyOverviewNotifier extends StateNotifier<AsyncValue<ArmyOverview>> {
  ArmyOverviewNotifier({required this.api, required this.socket})
    : super(const AsyncValue.loading()) {
    _bootstrap();
  }

  final GameApiDataSource api;
  final GameSocketDataSource socket;
  StreamSubscription<dynamic>? _socketSubscription;

  Future<void> _bootstrap() async {
    await refreshFromBarracks();
    _socketSubscription = socket.stream.listen(_onSocketMessage);
  }

  Future<void> refreshFromBarracks() async {
    try {
      final overview = await api.getBarracksOverview();
      state = AsyncValue.data(overview);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  void _onSocketMessage(dynamic raw) {
    final eventPayload = _extractArmyUpdatePayload(raw);
    if (eventPayload == null) {
      return;
    }

    final current = state.value ?? ArmyOverview.empty;
    final reserveCount = (eventPayload['reserveCount'] as num?)?.toInt();
    final reserveBs = (eventPayload['reserveBs'] as num?)?.toInt();

    // WS payload may omit warrior/support split; keep latest known split values.
    state = AsyncValue.data(
      current.copyWith(reserveCount: reserveCount, reserveBs: reserveBs),
    );
  }

  Map<String, dynamic>? _extractArmyUpdatePayload(dynamic raw) {
    Map<String, dynamic>? message;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          message = decoded;
        }
      } catch (_) {
        return null;
      }
    } else if (raw is Map<String, dynamic>) {
      message = raw;
    }

    if (message == null) {
      return null;
    }

    if (message.containsKey('reserveCount') || message.containsKey('reserveBs')) {
      return message;
    }

    final event = message['event'] as String?;
    final data = message['data'];
    if (event == 'army_update' && data is Map<String, dynamic>) {
      return data;
    }

    return null;
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }
}

