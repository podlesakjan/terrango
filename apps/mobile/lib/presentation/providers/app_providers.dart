import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/services/background_tracking_service.dart';
import '../../data/datasources/app_preferences_store.dart';
import '../../data/datasources/auth_session_store.dart';
import '../../data/datasources/game_api_data_source.dart';
import '../../data/datasources/game_socket_data_source.dart';
import '../../data/datasources/local_identity_store.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/entities/army_overview.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/hex_tile.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/usecases/get_visible_hexes_use_case.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  return AuthSessionStore();
});

final appPreferencesStoreProvider = Provider<AppPreferencesStore>((ref) {
  return AppPreferencesStore();
});

final localIdentityStoreProvider = Provider<LocalIdentityStore>((ref) {
  return LocalIdentityStore();
});

final backgroundTrackingServiceProvider = Provider<BackgroundTrackingServiceController>((ref) {
  return BackgroundTrackingServiceController();
});

final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, AsyncValue<AuthSession?>>((ref) {
      return AuthSessionNotifier(ref.watch(authSessionStoreProvider));
    });

final mapRepositoryProvider = Provider<MapRepository>((ref) {
  final repository = MapRepositoryImpl();
  ref.onDispose(repository.dispose);
  return repository;
});

final mapRepositorySyncProvider = Provider<void>((ref) {
  final repo = ref.watch(mapRepositoryProvider) as MapRepositoryImpl;

  void applyState(SessionSyncState state) {
    final mapSnapshot = state.mapSnapshot;
    if (mapSnapshot != null) {
      repo.applyMapSnapshot(mapSnapshot);
    }

    final mapGridUpdate = state.mapGridUpdate;
    if (mapGridUpdate != null) {
      repo.applyMapGridUpdate(mapGridUpdate);
    }

    final hexDetail = state.hexDetailUpdate;
    if (hexDetail != null) {
      repo.applyHexDetailUpdate(hexDetail);
    }

    final territoryUpdate = state.territoryUpdate;
    if (territoryUpdate != null) {
      final home = territoryUpdate['home'];
      if (home is Map<String, dynamic>) {
        repo.applyMapGridUpdate({
          'hexagons': [
            {
              'h3Index': home['centerH3Index'],
              'ownerName': home['name'],
              'color': '#2196F3',
              'hasGarrison': true,
              'isCenter': true,
            },
          ],
        });
      }
    }
  }

  applyState(ref.read(sessionSyncProvider));
  ref.listen<SessionSyncState>(sessionSyncProvider, (_, next) => applyState(next));
});

final gameApiDataSourceProvider = Provider<GameApiDataSource>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(authSessionProvider).valueOrNull;
  return GameApiDataSource(
    baseUrl: config.apiBaseUrl,
    bearerToken: session?.token ?? config.apiBearerToken,
  );
});

final gameSocketDataSourceProvider = Provider<GameSocketDataSource>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(authSessionProvider).valueOrNull;
  final socket = GameSocketDataSource(
    config.websocketUrl,
    bearerToken: session?.token ?? config.apiBearerToken,
  );
  ref.onDispose(socket.close);
  return socket;
});

final gameSocketEventControllerProvider =
    Provider<GameSocketEventController>((ref) {
      final controller = GameSocketEventController(ref.watch(gameSocketDataSourceProvider));
      ref.onDispose(controller.dispose);
      return controller;
    });

final sessionSyncProvider =
    StateNotifierProvider<SessionSyncNotifier, SessionSyncState>((ref) {
      return SessionSyncNotifier(ref.watch(gameSocketEventControllerProvider));
    });

final getVisibleHexesUseCaseProvider = Provider<GetVisibleHexesUseCase>((ref) {
  final repository = ref.watch(mapRepositoryProvider);
  return GetVisibleHexesUseCase(repository);
});

final visibleHexesProvider = StreamProvider<List<HexTile>>((ref) {
  ref.watch(mapRepositorySyncProvider);
  final repository = ref.watch(mapRepositoryProvider);
  return repository.watchVisibleHexes();
});

final hexDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, h3Index) {
  final gameApi = ref.watch(gameApiDataSourceProvider);
  return gameApi.getHexDetail(h3Index);
});

final nicknameProvider = StateProvider<String>((ref) => '');

final onboardingCompletedProvider =
    StateNotifierProvider<PersistedBoolNotifier, bool>((ref) {
      return PersistedBoolNotifier(
        store: ref.watch(appPreferencesStoreProvider),
        key: AppPreferencesStore.onboardingCompletedKey,
      );
    });

final wakeLockEnabledProvider =
    StateNotifierProvider<PersistedBoolNotifier, bool>((ref) {
      return PersistedBoolNotifier(
        store: ref.watch(appPreferencesStoreProvider),
        key: AppPreferencesStore.wakeLockEnabledKey,
      );
    });

final backgroundTrackingEnabledProvider =
    StateNotifierProvider<PersistedBoolNotifier, bool>((ref) {
      return PersistedBoolNotifier(
        store: ref.watch(appPreferencesStoreProvider),
        key: AppPreferencesStore.backgroundTrackingEnabledKey,
      );
    });

final armyOverviewProvider =
    StateNotifierProvider<ArmyOverviewNotifier, AsyncValue<ArmyOverview>>((
      ref,
    ) {
      return ArmyOverviewNotifier(
        api: ref.watch(gameApiDataSourceProvider),
        controller: ref.watch(gameSocketEventControllerProvider),
      );
    });

final territoryListProvider =
    StateNotifierProvider<TerritoryListNotifier, AsyncValue<Map<String, dynamic>>>(
      (ref) {
        return TerritoryListNotifier(
          api: ref.watch(gameApiDataSourceProvider),
          controller: ref.watch(gameSocketEventControllerProvider),
        );
      },
    );

final battleLogsProvider =
    StateNotifierProvider<BattleLogsNotifier, AsyncValue<List<Map<String, dynamic>>>>(
      (ref) {
        return BattleLogsNotifier(
          api: ref.watch(gameApiDataSourceProvider),
          controller: ref.watch(gameSocketEventControllerProvider),
        );
      },
    );

final profileProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<Map<String, dynamic>>>((ref) {
      return ProfileNotifier(ref.watch(gameApiDataSourceProvider), ref.read(authSessionProvider.notifier));
    });

class AuthSessionNotifier extends StateNotifier<AsyncValue<AuthSession?>> {
  AuthSessionNotifier(this._store) : super(const AsyncValue.loading()) {
    unawaited(_bootstrap());
  }

  final AuthSessionStore _store;

  Future<void> _bootstrap() async {
    try {
      final session = await _store.load();
      state = AsyncValue.data(session);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> saveSession(AuthSession session) async {
    await _store.save(session);
    state = AsyncValue.data(session);
  }

  Future<void> clear() async {
    await _store.clear();
    state = const AsyncValue.data(null);
  }
}

class PersistedBoolNotifier extends StateNotifier<bool> {
  PersistedBoolNotifier({
    required this._store,
    required this._key,
  }) :
       super(false) {
    unawaited(_bootstrap());
  }

  final AppPreferencesStore _store;
  final String _key;

  Future<void> _bootstrap() async {
    state = await _store.readBool(_key);
  }

  Future<void> setEnabled(bool value) async {
    if (state == value) {
      return;
    }
    state = value;
    await _store.writeBool(_key, value);
  }
}

class GameSocketEventController {
  GameSocketEventController(this.socket) {
    _socketSubscription = socket.stream.listen(_handleRawMessage);
    socket.onConnected(() {
      _connected = true;
      if (!_hasConnectedOnce) {
        _hasConnectedOnce = true;
        _emitSnapshotRequest();
        return;
      }
      _emitResumeSession();
      _emitMapSubscribe();
    });
    socket.onReconnected(() {
      _connected = true;
      _emitResumeSession();
      _emitMapSubscribe();
    });
    socket.onDisconnected((_) {
      _connected = false;
    });
  }

  final GameSocketDataSource socket;
  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<dynamic>? _socketSubscription;
  bool _connected = false;
  bool _hasConnectedOnce = false;
  List<String> _visibleH3Indexes = const [];
  DateTime _lastSyncTimestamp = DateTime.now().toUtc();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  void connect({Iterable<String>? visibleH3Indexes}) {
    if (visibleH3Indexes != null) {
      _visibleH3Indexes = visibleH3Indexes.toList(growable: false);
    }
    socket.connect();
  }

  void resumeSession() {
    if (!_connected) {
      socket.connect();
      return;
    }
    _emitResumeSession();
  }

  void disconnect() {
    socket.disconnect();
  }

  void sendVisibleArea(Iterable<String> visibleH3Indexes) {
    _visibleH3Indexes = visibleH3Indexes.toList(growable: false);
    _emitMapSubscribe();
  }

  void sendLocationUpdate({
    required double latitude,
    required double longitude,
    required String h3Index,
    required bool isMocked,
  }) {
    socket.emit('location_update', {
      'latitude': latitude,
      'longitude': longitude,
      'h3Index': h3Index,
      'isMocked': isMocked,
    });
  }

  void sendRecruitDevice({
    required String bluetoothId,
    required Map<String, dynamic> calculatedSoldier,
  }) {
    socket.emit('recruit_device', {
      'bluetoothId': bluetoothId,
      'calculatedSoldier': calculatedSoldier,
    });
  }

  void sendGarrisonModify({
    required String h3Index,
    required String action,
    required List<Map<String, dynamic>> composition,
  }) {
    socket.emit('garrison_modify', {
      'h3Index': h3Index,
      'action': action,
      'composition': composition,
    });
  }

  void sendReinforcements({
    required String targetH3Index,
    required List<Map<String, dynamic>> composition,
    int? burnSupportCount,
  }) {
    final payload = <String, dynamic>{
      'targetH3Index': targetH3Index,
      'composition': composition,
    };
    if (burnSupportCount != null) {
      payload['burnSupportCount'] = burnSupportCount;
    }
    socket.emit('send_reinforcements', payload);
  }

  void sendScoutHex(String targetH3Index) {
    socket.emit('scout_hex', {'targetH3Index': targetH3Index});
  }

  void sendAttackHex({
    required String targetH3Index,
    required List<Map<String, dynamic>> attackerComposition,
  }) {
    socket.emit('attack_hex', {
      'targetH3Index': targetH3Index,
      'attackerComposition': attackerComposition,
    });
  }

  void _handleRawMessage(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final event = raw['event'] as String?;
      if (event == 'map_snapshot' ||
          event == 'map_grid_update' ||
          event == 'hex_detail_update' ||
          event == 'army_update' ||
          event == 'territory_update' ||
          event == 'scout_result' ||
          event == 'battle_result') {
        _lastSyncTimestamp = DateTime.now().toUtc();
      }
      _eventsController.add(raw);
    }
  }

  void _emitResumeSession() {
    if (!_connected) {
      return;
    }
    socket.emit('resume_session', {
      'lastSyncTimestamp': _lastSyncTimestamp.toIso8601String(),
    });
  }

  void _emitSnapshotRequest() {
    if (_visibleH3Indexes.isEmpty || !_connected) {
      return;
    }
    socket.emit('request_map_snapshot', {
      'visibleH3Indexes': _visibleH3Indexes,
    });
  }

  void _emitMapSubscribe() {
    if (_visibleH3Indexes.isEmpty || !_connected) {
      return;
    }
    socket.emit('map_subscribe', {
      'visibleH3Indexes': _visibleH3Indexes,
    });
  }

  void dispose() {
    _socketSubscription?.cancel();
    _eventsController.close();
  }
}

class SessionSyncState {
  const SessionSyncState({
    this.mapSnapshot,
    this.mapGridUpdate,
    this.hexDetailUpdate,
    this.armyUpdate,
    this.territoryUpdate,
    this.scoutResult,
    this.battleResult,
    this.lastProcessedAt,
  });

  final Map<String, dynamic>? mapSnapshot;
  final Map<String, dynamic>? mapGridUpdate;
  final Map<String, dynamic>? hexDetailUpdate;
  final Map<String, dynamic>? armyUpdate;
  final Map<String, dynamic>? territoryUpdate;
  final Map<String, dynamic>? scoutResult;
  final Map<String, dynamic>? battleResult;
  final DateTime? lastProcessedAt;

  SessionSyncState copyWith({
    Map<String, dynamic>? mapSnapshot,
    Map<String, dynamic>? mapGridUpdate,
    Map<String, dynamic>? hexDetailUpdate,
    Map<String, dynamic>? armyUpdate,
    Map<String, dynamic>? territoryUpdate,
    Map<String, dynamic>? scoutResult,
    Map<String, dynamic>? battleResult,
    DateTime? lastProcessedAt,
  }) {
    return SessionSyncState(
      mapSnapshot: mapSnapshot ?? this.mapSnapshot,
      mapGridUpdate: mapGridUpdate ?? this.mapGridUpdate,
      hexDetailUpdate: hexDetailUpdate ?? this.hexDetailUpdate,
      armyUpdate: armyUpdate ?? this.armyUpdate,
      territoryUpdate: territoryUpdate ?? this.territoryUpdate,
      scoutResult: scoutResult ?? this.scoutResult,
      battleResult: battleResult ?? this.battleResult,
      lastProcessedAt: lastProcessedAt ?? this.lastProcessedAt,
    );
  }
}

class SessionSyncNotifier extends StateNotifier<SessionSyncState> {
  SessionSyncNotifier(this._controller) : super(const SessionSyncState()) {
    _subscription = _controller.events.listen(_onEvent);
  }

  final GameSocketEventController _controller;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  void _onEvent(Map<String, dynamic> eventEnvelope) {
    final eventName = eventEnvelope['event'] as String?;
    final payload = eventEnvelope['data'];
    if (payload is! Map<String, dynamic>) {
      return;
    }

    final now = DateTime.now().toUtc();
    if (eventName == 'map_snapshot') {
      state = state.copyWith(mapSnapshot: payload, lastProcessedAt: now);
      return;
    }
    if (eventName == 'map_grid_update') {
      state = state.copyWith(mapGridUpdate: payload, lastProcessedAt: now);
      return;
    }
    if (eventName == 'hex_detail_update') {
      state = state.copyWith(hexDetailUpdate: payload, lastProcessedAt: now);
      return;
    }
    if (eventName == 'army_update') {
      state = state.copyWith(armyUpdate: payload, lastProcessedAt: now);
      return;
    }
    if (eventName == 'territory_update') {
      state = state.copyWith(territoryUpdate: payload, lastProcessedAt: now);
      return;
    }
    if (eventName == 'scout_result') {
      state = state.copyWith(scoutResult: payload, lastProcessedAt: now);
      return;
    }
    if (eventName == 'battle_result') {
      state = state.copyWith(battleResult: payload, lastProcessedAt: now);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class ArmyOverviewNotifier extends StateNotifier<AsyncValue<ArmyOverview>> {
  ArmyOverviewNotifier({required this.api, required this.controller})
    : super(const AsyncValue.loading()) {
    _bootstrap();
  }

  final GameApiDataSource api;
  final GameSocketEventController controller;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  Future<void> _bootstrap() async {
    await refreshFromBarracks();
    _eventSubscription = controller.events.listen(_onSocketEvent);
  }

  Future<void> refreshFromBarracks() async {
    try {
      final overview = await api.getBarracksOverview();
      state = AsyncValue.data(overview);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  void _onSocketEvent(Map<String, dynamic> message) {
    final event = message['event'] as String?;
    if (event != 'army_update') {
      return;
    }

    unawaited(refreshFromBarracks());
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

class TerritoryListNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  TerritoryListNotifier({required this.api, required this.controller})
    : super(const AsyncValue.loading()) {
    unawaited(refresh());
    _eventSubscription = controller.events.listen(_onSocketEvent);
  }

  final GameApiDataSource api;
  final GameSocketEventController controller;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  void _onSocketEvent(Map<String, dynamic> message) {
    final event = message['event'] as String?;
    if (event == 'territory_update') {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    try {
      state = AsyncValue.data(await api.getTerritoryList());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> renameTerritory({
    required String territoryId,
    required String name,
  }) async {
    await api.renameTerritory(territoryId: territoryId, name: name);
    await refresh();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

class BattleLogsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  BattleLogsNotifier({required this.api, required this.controller})
    : super(const AsyncValue.loading()) {
    unawaited(refresh());
    _eventSubscription = controller.events.listen(_onSocketEvent);
  }

  final GameApiDataSource api;
  final GameSocketEventController controller;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  void _onSocketEvent(Map<String, dynamic> message) {
    final event = message['event'] as String?;
    if (event == 'battle_result' || event == 'scout_result') {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    try {
      state = AsyncValue.data(await api.getBattleLogs());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

class ProfileNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  ProfileNotifier(this.api, this.sessionNotifier) : super(const AsyncValue.loading()) {
    unawaited(refresh());
  }

  final GameApiDataSource api;
  final AuthSessionNotifier sessionNotifier;

  Future<void> refresh() async {
    try {
      state = AsyncValue.data(await api.getProfile());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> changeNickname(String nickname) async {
    await api.changeNickname(nickname: nickname);
    final session = sessionNotifier.state.valueOrNull;
    if (session != null) {
      await sessionNotifier.saveSession(AuthSession(userId: session.userId, token: session.token));
    }
    await refresh();
  }
}

