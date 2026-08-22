import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../providers/app_providers.dart';
import '../../providers/location_provider.dart';
import 'map_h3_helpers.dart';
import '../../../core/routing/app_router.dart';
import '../../../domain/entities/army_overview.dart';
import '../../../domain/entities/hex_tile.dart';


class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.focusH3Index});

  final String? focusH3Index;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  static const _hexSourceId = 'hex_source';
  static const _hexFillLayerId = 'hex_fill_layer';
  static const _hexLineLayerId = 'hex_line_layer';
  static const _hexTapInteractionId = 'hex-map-tap';

  final H3 _h3 = const H3Factory().load();


  MapboxMap? _mapboxMap;
  StreamSubscription<geolocator.Position>? _positionSubscription;
  bool _styleReady = false;
  bool _cameraInitialized = false;
  bool _tapInteractionInstalled = false;
  bool _socketInitialized = false;
  Set<String> _lastVisibleH3Indexes = const <String>{};
  Timer? _viewportSyncDebounce;
  Timer? _locationHeartbeatTimer;
  bool? _appliedWakeLockEnabled;
  bool? _appliedBackgroundTrackingEnabled;

  BannerAd? _bannerAd;
  bool _bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLocationTracking();
    _initBannerAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(gameSocketEventControllerProvider).resumeSession();
      _sendLocationUpdateFromCurrentPosition();
      _ensureLocationHeartbeat();
      _scheduleViewportSync(force: true);
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {

      _locationHeartbeatTimer?.cancel();
      _locationHeartbeatTimer = null;
    }
  }

  @override
  void dispose() {
    
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _viewportSyncDebounce?.cancel();
    _locationHeartbeatTimer?.cancel();
    ref.read(gameSocketEventControllerProvider).disconnect();
    _mapboxMap?.removeInteraction(_hexTapInteractionId);
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    final serviceEnabled = await geolocator.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    var permission = await geolocator.Geolocator.checkPermission();
    if (permission == geolocator.LocationPermission.denied) {
      permission = await geolocator.Geolocator.requestPermission();
    }
    if (permission == geolocator.LocationPermission.denied ||
        permission == geolocator.LocationPermission.deniedForever) {
      return;
    }

    final current = await geolocator.Geolocator.getCurrentPosition();
    _onNewPosition(current);
    _ensureLocationHeartbeat();

    _positionSubscription = geolocator.Geolocator.getPositionStream(
      locationSettings: const geolocator.LocationSettings(
        accuracy: geolocator.LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(_onNewPosition);
  }

  Future<void> _onNewPosition(geolocator.Position position) async {
    final h3Index = await _toH3IndexString(position.latitude, position.longitude);

    ref.read(locationProvider.notifier).updateLocation(position, h3Index);

    _sendLocationUpdate(position, h3Index);
    _refreshHexSource();
    _updateGpsPuck();
    _setInitialCameraIfPossible();
  }

  void _ensureLocationHeartbeat() {
    if (_locationHeartbeatTimer != null) {
      return;
    }

    _locationHeartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _sendLocationUpdateFromCurrentPosition();
    });
  }

  void _sendLocationUpdateFromCurrentPosition() {
    final location = ref.read(locationProvider);
    final position = location.position;
    final h3Index = location.h3Index;
    if (position == null || h3Index == null || h3Index.isEmpty) {
      return;
    }
    _sendLocationUpdate(position, h3Index);
  }

  void _sendLocationUpdate(geolocator.Position position, String h3Index) {
    ref.read(gameSocketEventControllerProvider).sendLocationUpdate(
      latitude: position.latitude,
      longitude: position.longitude,
      h3Index: h3Index,
      isMocked: position.isMocked,
    );
  }

  void _initBannerAd() {
    final config = ref.read(appConfigProvider);
    final adUnitId = Platform.isIOS
        ? config.admobBannerIosUnitId
        : config.admobBannerAndroidUnitId;

    final ad = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _bannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );

    ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final hexesAsync = ref.watch(visibleHexesProvider);
    final nickname = ref.watch(nicknameProvider);
    final armyOverviewAsync = ref.watch(armyOverviewProvider);
    final wakeLockEnabled = ref.watch(wakeLockEnabledProvider);
    final backgroundTrackingEnabled = ref.watch(backgroundTrackingEnabledProvider);

    ref.listen<bool>(wakeLockEnabledProvider, (_, next) {
      unawaited(_applyWakeLock(next));
    });

    ref.listen<bool>(backgroundTrackingEnabledProvider, (_, next) {
      unawaited(_applyBackgroundTracking(next));
    });

    ref.listen<SessionSyncState>(sessionSyncProvider, (previous, next) {
      if (previous?.hexDetailUpdate != next.hexDetailUpdate) {
        _showInfo('Hex details were refreshed from the server.');
      }
      if (previous?.armyUpdate != next.armyUpdate) {
        _showInfo('Army state was refreshed from the server.');
      }
      if (previous?.territoryUpdate != next.territoryUpdate) {
        _showInfo('Territory state was refreshed from the server.');
      }
      if (previous?.scoutResult != next.scoutResult) {
        _showInfo(_describeScoutResult(next.scoutResult));
      }
      if (previous?.battleResult != next.battleResult && next.battleResult != null) {
        _showBattleResult(next.battleResult!);
      }
    });

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _centerMapOnUser,
        child: const Icon(Icons.my_location),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: hexesAsync.when(
              data: (hexes) {
                return MapWidget(
                  key: const ValueKey('terrango_mapbox'),
                  styleUri: config.mapOutdoorStyleUri,
                  onMapCreated: (mapboxMap) async {
                    _mapboxMap = mapboxMap;
                    if (!_tapInteractionInstalled) {
                      _tapInteractionInstalled = true;
                      mapboxMap.addInteraction(
                        TapInteraction.onMap((gestureContext) async {
                          if (gestureContext.gestureState != GestureState.ended) {
                            return;
                          }
                          final tappedH3 = await _toH3IndexString(
                            gestureContext.point.coordinates.lat.toDouble(),
                            gestureContext.point.coordinates.lng.toDouble(),
                          );
                          final currentHexes = ref.read(visibleHexesProvider).value ?? const <HexTile>[];
                          final tappedHex = _findHexByH3Index(currentHexes, tappedH3);
                          if (tappedHex != null && mounted) {
                            _openHexContextSheet(context, tappedHex, currentHexes);
                          }
                        }),
                        interactionID: _hexTapInteractionId,
                      );
                    }
                  },
                  onStyleLoadedListener: (_) async {
                    _styleReady = true;
                    await _ensureGameLayers();
                    _refreshHexSource();
                    _updateGpsPuck();

                    if (!_cameraInitialized) {
                      await _setInitialCameraIfPossible();
                    }

                    _scheduleViewportSync(force: true);
                  },
                  onCameraChangeListener: (_) {
                    _scheduleViewportSync();
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load map: $error'),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _StatusBar(
              nickname: nickname.isEmpty ? 'Operative' : nickname,
              hexesAsync: hexesAsync,
              armyOverviewAsync: armyOverviewAsync,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _QuickActionButton(
                      label: 'RECRUITMENT',
                      onPressed: () => context.push(AppRoute.recruitment),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickActionButton(
                      label: 'BARRACKS',
                      onPressed: () => context.push(AppRoute.barracks),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickActionButton(
                      label: 'BASES',
                      onPressed: () => context.push(AppRoute.bases),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_bannerLoaded && _bannerAd != null)
                SizedBox(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                )
              else
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Color(0x221D2633),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    border: Border.fromBorderSide(BorderSide(color: Color(0x332196F3))),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Advertisement',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyWakeLock(bool wakeLockEnabled) async {
    if (_appliedWakeLockEnabled != wakeLockEnabled) {
      _appliedWakeLockEnabled = wakeLockEnabled;
      try {
        await WakelockPlus.toggle(enable: wakeLockEnabled);
      } catch (_) {
        // Ignore unsupported-platform/plugin errors outside mobile runtimes.
      }
    }
  }

  Future<void> _applyBackgroundTracking(bool backgroundTrackingEnabled) async {
    if (_appliedBackgroundTrackingEnabled != backgroundTrackingEnabled) {
      _appliedBackgroundTrackingEnabled = backgroundTrackingEnabled;
      try {
        await ref.read(backgroundTrackingServiceProvider).setEnabled(
          backgroundTrackingEnabled,
        );
      } catch (_) {
        // Ignore runtime service issues here; the dedicated settings screen surfaces them.
      }
    }
  }

  HexTile? _findHexByH3Index(List<HexTile> hexes, String h3Index) {
    for (final hex in hexes) {
      if (hex.h3Index == h3Index) {
        return hex;
      }
    }
    return null;
  }

  Point _initialCenterFromState(List<HexTile> hexes) {
    final currentPosition = ref.read(locationProvider).position;
    if (currentPosition != null) {
      return Point(
        coordinates: Position(
          currentPosition.longitude,
          currentPosition.latitude,
        ),
      );
    }

    if (hexes.isNotEmpty) {
      final center = _h3.h3ToGeo(_parseH3(hexes.first.h3Index));
      return Point(coordinates: Position(center.lon, center.lat));
    }

    return Point(coordinates: Position(14.4378, 50.0755));
  }

  Future<void> _ensureGameLayers() async {
    final map = _mapboxMap;
    if (map == null || !_styleReady) {
      return;
    }

    try {
      await map.style.removeStyleLayer(_hexLineLayerId);
    } catch (_) {}
    try {
      await map.style.removeStyleLayer(_hexFillLayerId);
    } catch (_) {}
    try {
      await map.style.removeStyleSource(_hexSourceId);
    } catch (_) {}

    await map.style.addSource(
      GeoJsonSource(
        id: _hexSourceId,
        data: jsonEncode(_buildHexFeatureCollection(
            ref.read(visibleHexesProvider).value ?? const [],
            ref.read(locationProvider).h3Index,
            _h3)),
      ),
    );

    await map.style.addLayer(
      FillLayer(
        id: _hexFillLayerId,
        sourceId: _hexSourceId,
        fillOpacity: 0.7,
        fillColorExpression: [
          'match',
          ['get', 'state'],
          'owned',
          '#2196F3',
          'enemy',
          '#E53935',
          'free',
          '#BDBDBD',
          '#9E9E9E',
        ],
      ),
    );

    await map.style.addLayer(
      LineLayer(
        id: _hexLineLayerId,
        sourceId: _hexSourceId,
        lineOpacity: 1.0,
        lineColorExpression: [
          'case',
          ['==', ['get', 'isCurrent'], true],
          '#FFD54F',
          ['==', ['get', 'state'], 'owned'],
          '#1976D2',
          ['==', ['get', 'state'], 'enemy'],
          '#D32F2F',
          '#757575',
        ],
        lineWidthExpression: [
          'case',
          ['==', ['get', 'isCurrent'], true],
          3.5,
          2.5,
        ],
      ),
    );
  }

  Future<void> _refreshHexSource() async {
    final map = _mapboxMap;
    if (map == null || !_styleReady) {
      return;
    }

    final hexes = ref.read(visibleHexesProvider).value;
    if (hexes == null) {
      return;
    }

    final source = await map.style.getSource(_hexSourceId);
    if (source is GeoJsonSource) {
      final h3 = _h3;
      final currentH3Index = ref.read(locationProvider).h3Index;
      final geoJson = await Isolate.run(
        () => jsonEncode(
            _buildHexFeatureCollection(hexes, currentH3Index, h3)),
      );
      await source.updateGeoJSON(geoJson);
    }
  }

  static Map<String, dynamic> _buildHexFeatureCollection(
      List<HexTile> hexes, String? currentH3Index, H3 h3) {
    final features = <Map<String, dynamic>>[];

    for (final hex in hexes) {
      final h3Index = BigInt.parse(hex.h3Index, radix: 16);
      final boundary = h3.h3ToGeoBoundary(h3Index);
      if (boundary.isEmpty) {
        continue;
      }

      final ring = boundary
          .map((coord) => [coord.lon, coord.lat])
          .toList(growable: true);
      ring.add([boundary.first.lon, boundary.first.lat]);

      features.add({
        'type': 'Feature',
        'properties': {
          'h3Index': hex.h3Index,
          'state': switch (hex.state) {
            HexState.free => 'free',
            HexState.owned => 'owned',
            HexState.enemy => 'enemy',
          },
          'ownerName': hex.ownerName,
          'hasGarrison': hex.hasGarrison,
          'isCenter': hex.isCenter,
          'isCurrent': hex.h3Index == currentH3Index,
        },
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
      });
    }

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  Future<void> _updateGpsPuck() async {
    final map = _mapboxMap;
    if (map == null || !_styleReady) {
      return;
    }

    await map.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        showAccuracyRing: true,
        puckBearingEnabled: true,
      ),
    );
  }

  Future<void> _setInitialCameraIfPossible() async {
    if (_cameraInitialized) {
      return;
    }

    final map = _mapboxMap;
    if (map == null || !_styleReady) {
      return;
    }

      final focusedH3Index = widget.focusH3Index?.trim();
    if (focusedH3Index != null && focusedH3Index.isNotEmpty) {
      final center = _h3.h3ToGeo(_parseH3(focusedH3Index));
      _cameraInitialized = true;
      await map.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(center.lon, center.lat)),
          zoom: ref.read(appConfigProvider).mapDefaultZoom,
        ),
      );
      _scheduleViewportSync();
      return;
    }

    final position = ref.read(locationProvider).position;
    if (position != null) {
      _cameraInitialized = true;
      await map.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(position.longitude, position.latitude),
          ),
          zoom: ref.read(appConfigProvider).mapDefaultZoom,
        ),
      );
      _scheduleViewportSync();
    }
  }

  void _scheduleViewportSync({bool force = false}) {
    _viewportSyncDebounce?.cancel();
    _viewportSyncDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_syncVisibleHexesFromViewport(forceSnapshot: force));
    });
  }

  Future<void> _syncVisibleHexesFromViewport({bool forceSnapshot = false}) async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }

    try {
      final cameraState = await map.getCameraState();
      final center = cameraState.center.coordinates;
      final zoom = cameraState.zoom;
      final centerH3Index = await _toH3IndexString(
        center.lat.toDouble(),
        center.lng.toDouble(),
      );

      final radius = _viewportRadiusFromZoom(zoom);
      final visibleIndexes = await MapH3Calculations.kRing(centerH3Index, radius);

      final controller = ref.read(gameSocketEventControllerProvider);
      if (!_socketInitialized || forceSnapshot) {
        _socketInitialized = true;
        controller.connect(visibleH3Indexes: visibleIndexes);
      }

      if (visibleIndexes.length != _lastVisibleH3Indexes.length ||
          !visibleIndexes.containsAll(_lastVisibleH3Indexes)) {
        _lastVisibleH3Indexes = visibleIndexes;
        controller.sendVisibleArea(visibleIndexes);
      }
    } catch (_) {
      // Ignore viewport sync failures and retry on next camera change.
    }
  }

  int _viewportRadiusFromZoom(double zoom) {
    if (zoom >= 15) return 3;
    if (zoom >= 13) return 5;
    if (zoom >= 11) return 7;
    if (zoom >= 9) return 9;
    return 10;
  }

  void _openHexContextSheet(
    BuildContext context,
    HexTile hex,
    List<HexTile> allHexes,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131A24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 2 / 3,
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _HexContextSheet(
            hex: hex,
            currentH3Index: ref.read(locationProvider).h3Index,
            onEstablishPressed: (territoryName) => _establishTerritory(
              hex,
              territoryName,
            ),
            onOccupyPressed: (composition, territoryName) => _occupyHex(
              hex,
              composition,
              territoryName,
            ),
            onSetCenterChanged: (value) => _setCenter(hex, value),
            onDeployPressed: (composition) => _sendGarrisonModify(
              hex: hex,
              action: 'DEPLOY',
              composition: composition,
            ),
            onWithdrawPressed: (composition) => _sendGarrisonModify(
              hex: hex,
              action: 'WITHDRAW',
              composition: composition,
            ),
            onSendReinforcementPressed: (composition) => _sendReinforcements(
              hex: hex,
              composition: composition,
              burnSupportCount: null,
            ),
            onSendReinforcementBurnPressed: (composition) => _sendReinforcements(
              hex: hex,
              composition: composition,
              burnSupportCount: 1,
            ),
            onSendReinforcementLossyPressed: (composition) => _sendReinforcements(
              hex: hex,
              composition: composition,
              burnSupportCount: null,
            ),
            onScoutPressed: () => _scoutHex(hex),
            onAttackPressed: (composition) => _attackHex(hex, composition),
          ),
        );
      },
    );
  }

  Future<void> _establishTerritory(HexTile hex, String territoryName) async {
    try {
      await ref.read(gameApiDataSourceProvider).establishTerritory(
            h3Index: hex.h3Index,
            name: territoryName,
          );
      _showInfo('Home territory established.');
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      unawaited(ref.read(territoryListProvider.notifier).refresh());
      unawaited(ref.read(armyOverviewProvider.notifier).refreshFromBarracks());
    } catch (error) {
      _showInfo('Failed to establish home territory: $error');
    }
  }

  Future<void> _occupyHex(
    HexTile hex,
    List<Map<String, dynamic>> composition,
    String? territoryName,
  ) async {
    final currentPosition = ref.read(locationProvider).position;
    if (currentPosition == null) {
      _showInfo('Please wait for GPS location first.');
      return;
    }

    if (composition.isEmpty) {
      _showInfo('Select at least one reserve bucket to occupy this hex.');
      return;
    }

    try {
      await ref.read(gameApiDataSourceProvider).occupyHex(
            h3Index: hex.h3Index,
            latitude: currentPosition.latitude,
            longitude: currentPosition.longitude,
            garrisonComposition: composition,
            territoryName: territoryName,
          );
      _showInfo('Territory occupation request was sent.');
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      unawaited(ref.read(territoryListProvider.notifier).refresh());
      unawaited(ref.read(armyOverviewProvider.notifier).refreshFromBarracks());
    } catch (error) {
      _showInfo('Occupation failed: $error');
    }
  }

  Future<void> _setCenter(HexTile hex, bool value) async {
    if (!value) {
      return;
    }

    try {
      final detail = await ref.read(gameApiDataSourceProvider).getHexDetail(hex.h3Index);
      final territory = detail['territory'];
      final territoryId = territory is Map<String, dynamic>
          ? territory['id'] as String?
          : null;

      if (territoryId == null || territoryId.isEmpty) {
        _showInfo('Cannot determine territoryId for center change.');
        return;
      }

      await ref
          .read(gameApiDataSourceProvider)
          .setTerritoryCenter(territoryId: territoryId, h3Index: hex.h3Index);
      _showInfo('Center has been changed.');
      ref.invalidate(visibleHexesProvider);
    } catch (error) {
      _showInfo('Center change failed: $error');
    }
  }

  Future<void> _sendGarrisonModify(
    {
    required HexTile hex,
    required String action,
    required List<Map<String, dynamic>> composition,
  }) async {
    final controller = ref.read(gameSocketEventControllerProvider);
    controller.sendGarrisonModify(
      h3Index: hex.h3Index,
      action: action,
      composition: composition,
    );
    _showInfo('Action $action was sent. Waiting for server confirmation...');
  }

  Future<void> _sendReinforcements(
    {
    required HexTile hex,
    required List<Map<String, dynamic>> composition,
    required int? burnSupportCount,
  }) async {
    if (!_canSendReinforcements(hex)) {
      _showInfo('Reinforcements are available only while this hex is under attack.');
      return;
    }

    final controller = ref.read(gameSocketEventControllerProvider);
    controller.sendReinforcements(
      targetH3Index: hex.h3Index,
      composition: composition,
      burnSupportCount: burnSupportCount,
    );

    _showInfo(
      burnSupportCount == null
          ? 'Reinforcement request sent with transit losses.'
          : 'Reinforcement request sent by burning 1 SUPPORT.',
    );
  }

  Future<void> _scoutHex(HexTile hex) async {
    final controller = ref.read(gameSocketEventControllerProvider);
    controller.sendScoutHex(hex.h3Index);
    _showInfo('Scout action was sent.');
  }

  Future<void> _attackHex(HexTile hex, List<Map<String, dynamic>> composition) async {
    if (ref.read(locationProvider).h3Index != hex.h3Index) {
      _showInfo('You can attack only while physically standing in this hex.');
      return;
    }

    final controller = ref.read(gameSocketEventControllerProvider);
    controller.sendAttackHex(
      targetH3Index: hex.h3Index,
      attackerComposition: composition,
    );
    _showInfo('Attack request was sent.');
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  BigInt _parseH3(String h3Index) => BigInt.parse(h3Index, radix: 16);

  Future<String> _toH3IndexString(double lat, double lon) {
    return MapH3Calculations.geoToH3(lat, lon);
  }

  bool _canSendReinforcements(HexTile hex) {
    if (hex.state != HexState.owned) {
      return false;
    }

    final sync = ref.read(sessionSyncProvider);
    final hexDetail = sync.hexDetailUpdate;
    if (hexDetail is Map<String, dynamic>) {
      final sameHex = hexDetail['h3Index'] == hex.h3Index;
      final attackFlags = [
        hexDetail['isUnderAttack'],
        hexDetail['underAttack'],
        hexDetail['battleActive'],
        hexDetail['pendingBattle'],
      ];
      if (sameHex && attackFlags.any((flag) => flag == true)) {
        return true;
      }
    }

    final battleResult = sync.battleResult;
    if (battleResult != null && battleResult['h3Index'] == hex.h3Index) {
      return battleResult['result'] == 'VICTORY' || battleResult['result'] == 'DEFEAT';
    }

    return false;
  }

  String _describeScoutResult(Map<String, dynamic>? payload) {
    if (payload == null) {
      return 'Scout result received.';
    }

    final status = (payload['status'] as String?)?.toUpperCase();
    final targetH3Index = payload['targetH3Index'] as String?;
    if (status == 'JAMMED') {
      return 'Scout was jammed${targetH3Index != null ? ' for $targetH3Index' : ''}.';
    }
    if (status == 'SUCCESS') {
      final revealedBs = (payload['revealedBs'] as num?)?.toInt();
      return 'Scout succeeded${targetH3Index != null ? ' on $targetH3Index' : ''}: ${revealedBs ?? 0} BS revealed.';
    }
    return 'Scout result received.';
  }

  void _showBattleResult(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final result = (payload['result'] as String?)?.toUpperCase() ?? 'UNKNOWN';
    final dead = (payload['myDeadCount'] as num?)?.toInt() ?? 0;
    final survivors = payload['mySurvivors'];
    final survivorCount = survivors is List ? survivors.length : 0;

    final title = 'Battle $result!';
    final content = 'Losses: $dead\nSurvivors: $survivorCount';

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('Dismiss'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }



  void _centerMapOnUser() {
    final position = ref.read(locationProvider).position;
    final map = _mapboxMap;
    if (position == null || map == null) {
      _showInfo('Current location not available.');
      return;
    }

    map.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: ref.read(appConfigProvider).mapDefaultZoom,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.nickname,
    required this.hexesAsync,
    required this.armyOverviewAsync,
  });

  final String nickname;
  final AsyncValue<List<HexTile>> hexesAsync;
  final AsyncValue<ArmyOverview> armyOverviewAsync;

  @override
  Widget build(BuildContext context) {
    final hexes = hexesAsync.value ?? const <HexTile>[];
    final occupied = hexes.where((h) => h.state == HexState.owned).length;
    final army = armyOverviewAsync.valueOrNull;
    final warriorCount = army?.warriorCount ?? 0;
    final supportCount = army?.supportCount ?? 0;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xAA0B0F16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text('HEX $occupied'),
                const SizedBox(width: 12),
                Text('⚔ $warriorCount / 📡 $supportCount'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}typedef _EstablishTerritoryCallback = Future<void> Function(String territoryName);
typedef _OccupyHexCallback = Future<void> Function(
  List<Map<String, dynamic>> composition,
  String? territoryName,
);

class _HexContextSheet extends ConsumerWidget {
  const _HexContextSheet({
    required this.hex,
    required this.currentH3Index,
    required this.onEstablishPressed,
    required this.onOccupyPressed,
    required this.onSetCenterChanged,
    required this.onDeployPressed,
    required this.onWithdrawPressed,
    required this.onSendReinforcementPressed,
    required this.onSendReinforcementBurnPressed,
    required this.onSendReinforcementLossyPressed,
    required this.onScoutPressed,
    required this.onAttackPressed,
  });

  final HexTile hex;
  final String? currentH3Index;
  final _EstablishTerritoryCallback onEstablishPressed;
  final _OccupyHexCallback onOccupyPressed;
  final ValueChanged<bool> onSetCenterChanged;
  final void Function(List<Map<String, dynamic>> composition) onDeployPressed;
  final void Function(List<Map<String, dynamic>> composition) onWithdrawPressed;
  final void Function(List<Map<String, dynamic>> composition)
      onSendReinforcementPressed;
  final void Function(List<Map<String, dynamic>> composition)
      onSendReinforcementBurnPressed;
  final void Function(List<Map<String, dynamic>> composition)
      onSendReinforcementLossyPressed;
  final VoidCallback onScoutPressed;
  final void Function(List<Map<String, dynamic>> composition) onAttackPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(hexDetailProvider(hex.h3Index));
    final territoryNameController = useTextEditingController(
      text: hex.state == HexState.free
          ? 'New Outpost'
          : hex.territoryName ?? '',
    );

    ref.listen(gameSocketEventControllerProvider.select((s) => s.events),
        (_, eventStream) {
      eventStream.listen((event) {
        if (event['data']?['h3Index'] == hex.h3Index) {
          ref.invalidate(hexDetailProvider(hex.h3Index));
        }
      });
    });

    return SafeArea(
      top: false,
      child: detailAsync.when(
        data: (detail) =>
            _buildDetailContent(context, ref, detail, territoryNameController),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Failed to load hex details: $error'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.invalidate(hexDetailProvider(hex.h3Index)),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailContent(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> detail,
    TextEditingController territoryNameController,
  ) {
    final state = (detail['state'] as String? ?? '').toUpperCase();
    final army = ref.watch(armyOverviewProvider).valueOrNull;
    final reserveBuckets = army?.reserves ?? const <SoldierBucketSummary>[];
    final territoryData = ref.watch(territoryListProvider).valueOrNull;
    final hasHomeTerritory =
        territoryData != null && territoryData['home'] != null;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_sheetTitle(state),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(hex.h3Index, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (state == 'FREE')
            _buildFreeContent(context, detail, reserveBuckets,
                hasHomeTerritory, territoryNameController),
          if (state == 'OWNED')
            _buildOwnedContent(context, ref, detail, reserveBuckets),
          if (state == 'ENEMY')
            _buildEnemyContent(context, detail, reserveBuckets),
        ],
      ),
    );
  }

  Widget _buildFreeContent(
    BuildContext context,
    Map<String, dynamic> detail,
    List<SoldierBucketSummary> reserveBuckets,
    bool hasHomeTerritory,
    TextEditingController territoryNameController,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasHomeTerritory
              ? 'This hex is free and can be occupied from your reserves.'
              : 'This is your first claimed hex. Establish your Home Territory here.',
        ),
        const SizedBox(height: 8),
        if (!hasHomeTerritory)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: territoryNameController,
                  decoration: const InputDecoration(
                    labelText: 'Home territory name',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => onEstablishPressed(
                  territoryNameController.text.trim().isEmpty
                      ? 'Home Territory'
                      : territoryNameController.text.trim(),
                ),
                icon: const Icon(Icons.home_filled),
                label: const Text('Establish'),
              ),
            ],
          )
        else ...[
          TextField(
            controller: territoryNameController,
            decoration: const InputDecoration(
              labelText: 'New territory name (optional)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          _BucketActionList(
            title: 'Reserve composition',
            emptyMessage: 'No reserve units available. Open Recruitment first.',
            buckets: reserveBuckets,
            actions: [
              _BucketAction(
                label: 'Occupy territory',
                onPressed: (bucket) async {
                  final count =
                      await _promptCount(context, bucket, 'Occupy territory');
                  if (count == null) {
                    return;
                  }
                  await onOccupyPressed(
                    [_payloadFromBucket(bucket, count)],
                    territoryNameController.text.trim().isEmpty
                        ? null
                        : territoryNameController.text.trim(),
                  );
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildOwnedContent(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> detail,
    List<SoldierBucketSummary> reserveBuckets,
  ) {
    final territory =
        detail['territory'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final territoryType = (territory['type'] as String? ?? '').toUpperCase();
    final garrison =
        detail['garrison'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final garrisonBuckets = _bucketsFromDynamicList(garrison['composition']);
    final defenseActive = _isDefenseActive(ref.watch(sessionSyncProvider));
    final canChangeCenter = territoryType == 'HOME' || detail['isCenter'] == true;
    final bonus = (detail['backgroundBonusPercent'] as num?)?.toInt() ?? 0;
    final garrisonSoldiers = (garrison['soldierCount'] as num?)?.toInt() ?? 0;
    final garrisonBs = (garrison['totalBs'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'Territory name: ${(territory['name'] as String?) ?? 'Unknown territory'}'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.workspace_premium_outlined, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Set as Center 👑')),
            Switch(
              value: detail['isCenter'] == true,
              onChanged: canChangeCenter ? onSetCenterChanged : null,
            ),
          ],
        ),
        if (!canChangeCenter)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
                'Only hexes inside the Home Territory can be assigned as the center.'),
          ),
        Text('Garrison: $garrisonSoldiers soldiers / $garrisonBs BS'),
        const SizedBox(height: 4),
        Text('Background Bonus: +$bonus% per neighboring owned hex'),
        const SizedBox(height: 12),
        _BucketActionList(
          title: 'Current garrison',
          emptyMessage: 'No soldiers are currently deployed on this hex.',
          buckets: garrisonBuckets,
          actions: [
            _BucketAction(
              label: 'Withdraw to reserves',
              onPressed: (bucket) async {
                final count = await _promptCount(
                    context, bucket, 'Withdraw to reserves');
                if (count == null) {
                  return;
                }
                onWithdrawPressed([_payloadFromBucket(bucket, count)]);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BucketActionList(
          title: 'Reserve composition',
          emptyMessage: 'No reserve units available.',
          buckets: reserveBuckets,
          actions: [
            _BucketAction(
              label: 'Reinforce garrison',
              onPressed: (bucket) async {
                final count =
                    await _promptCount(context, bucket, 'Reinforce garrison');
                if (count == null) {
                  return;
                }
                onDeployPressed([_payloadFromBucket(bucket, count)]);
              },
            ),
            if (territoryType == 'HOME')
              _BucketAction(
                label: 'Send instantly',
                enabled: defenseActive,
                onPressed: (bucket) async {
                  final count = await _promptCount(
                      context, bucket, 'Send instant reinforcements');
                  if (count == null) {
                    return;
                  }
                  onSendReinforcementPressed(
                      [_payloadFromBucket(bucket, count)]);
                },
              )
            else ...[
              _BucketAction(
                label: 'Burn 1 Support',
                enabled: defenseActive,
                onPressed: (bucket) async {
                  final count = await _promptCount(
                      context, bucket, 'Send reinforced outpost support');
                  if (count == null) {
                    return;
                  }
                  onSendReinforcementBurnPressed(
                      [_payloadFromBucket(bucket, count)]);
                },
              ),
              _BucketAction(
                label: 'Send with 40% losses',
                enabled: defenseActive,
                onPressed: (bucket) async {
                  final count = await _promptCount(
                      context, bucket, 'Send lossy reinforcements');
                  if (count == null) {
                    return;
                  }
                  onSendReinforcementLossyPressed(
                      [_payloadFromBucket(bucket, count)]);
                },
              ),
            ],
          ],
        ),
        if (!defenseActive)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Remote reinforcements become available only while this hex is under active attack.',
            ),
          ),
      ],
    );
  }

  Widget _buildEnemyContent(
    BuildContext context,
    Map<String, dynamic> detail,
    List<SoldierBucketSummary> reserveBuckets,
  ) {
    final canScout = detail['canScout'] == true;
    final canAttack = detail['canAttack'] == true;
    final isStandingInHex = currentH3Index == hex.h3Index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Owner: ${(detail['ownerName'] as String?) ?? 'Unknown'}'),
        const SizedBox(height: 8),
        Text('Fog of war: ${(detail['fogOfWar'] as String?) ?? '??? BS'}'),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: canScout ? onScoutPressed : null,
              child: const Text('Scout'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: null,
              child: const Text('ATTACK!'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!canScout)
          const Text(
              'Scouting requires a Support unit with the Scout skill while standing in this hex.'),
        if (!isStandingInHex)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('To attack, you must physically stand in this hex.'),
          ),
        const SizedBox(height: 12),
        _BucketActionList(
          title: 'Reserve composition',
          emptyMessage: 'No reserve units available for an attack.',
          buckets: reserveBuckets,
          actions: [
            _BucketAction(
              label: 'ATTACK!',
              enabled: canAttack,
              onPressed: (bucket) async {
                final count =
                    await _promptCount(context, bucket, 'Launch attack');
                if (count == null) {
                  return;
                }
                onAttackPressed([_payloadFromBucket(bucket, count)]);
              },
            ),
          ],
        ),
      ],
    );
  }

  String _sheetTitle(String state) {
    return switch (state) {
      'FREE' => 'Free hex',
      'OWNED' => 'Your hex',
      'ENEMY' => 'Enemy hex',
      _ => 'Hex details',
    };
  }

  List<SoldierBucketSummary> _bucketsFromDynamicList(dynamic raw) {
    return (raw as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(SoldierBucketSummary.fromServer)
        .where((bucket) => bucket.count > 0)
        .toList(growable: false);
  }

  Map<String, dynamic> _payloadFromBucket(
      SoldierBucketSummary bucket, int count) {
    final safeCount = count.clamp(1, bucket.count);
    final totalBs = bucket.count <= 0
        ? 0
        : ((bucket.totalBs * safeCount) / bucket.count).round();
    return {
      'type': bucket.type,
      'rarity': bucket.rarity,
      'skill': bucket.skill,
      'count': safeCount,
      'totalBs': totalBs,
    };
  }

  Future<int?> _promptCount(
      BuildContext context, SoldierBucketSummary bucket, String title) async {
    final controller = TextEditingController(text: '1');
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Count (max ${bucket.count})',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed <= 0) {
                  Navigator.of(dialogContext).pop();
                  return;
                }
                Navigator.of(dialogContext).pop(parsed.clamp(1, bucket.count));
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  bool _isDefenseActive(SessionSyncState sync) {
    final hexDetail = sync.hexDetailUpdate;
    if (hexDetail != null) {
      final sameHex = hexDetail['h3Index'] == hex.h3Index;
      final attackFlags = [
        hexDetail['isUnderAttack'],
        hexDetail['underAttack'],
        hexDetail['battleActive'],
        hexDetail['pendingBattle'],
      ];
      if (sameHex && attackFlags.any((flag) => flag == true)) {
        return true;
      }
    }

    final battleResult = sync.battleResult;
    if (battleResult != null && battleResult['h3Index'] == hex.h3Index) {
      return battleResult['result'] == 'VICTORY' ||
          battleResult['result'] == 'DEFEAT';
    }

    return false;
  }
}

class _BucketActionList extends StatelessWidget {
  const _BucketActionList({
    required this.title,
    required this.emptyMessage,
    required this.buckets,
    required this.actions,
  });

  final String title;
  final String emptyMessage;
  final List<SoldierBucketSummary> buckets;
  final List<_BucketAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (buckets.isEmpty)
          Text(emptyMessage)
        else
          ...buckets.map(
            (bucket) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_bucketLabel(bucket), style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text('Count ${bucket.count} • ${bucket.totalBs} BS total'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final action in actions)
                            FilledButton.tonal(
                              onPressed: action.enabled
                                  ? () => action.onPressed(bucket)
                                  : null,
                              child: Text(action.label),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _bucketLabel(SoldierBucketSummary bucket) {
    final rarity = bucket.rarity.toLowerCase();
    final rarityLabel = rarity.isEmpty
        ? bucket.rarity
        : '${rarity[0].toUpperCase()}${rarity.substring(1)}';
    if (bucket.type == 'SUPPORT' && bucket.skill != null) {
      final skill = bucket.skill!.toLowerCase();
      final skillLabel = skill.isEmpty
          ? bucket.skill!
          : '${skill[0].toUpperCase()}${skill.substring(1)}';
      return '$rarityLabel Support • $skillLabel';
    }
    return '$rarityLabel ${bucket.type == 'WARRIOR' ? 'Warrior' : 'Support'}';
  }
}

class _BucketAction {
  const _BucketAction({
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final bool enabled;
  final Future<void> Function(SoldierBucketSummary bucket) onPressed;
}

