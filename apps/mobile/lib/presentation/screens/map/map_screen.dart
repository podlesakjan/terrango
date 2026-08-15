import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../domain/entities/army_overview.dart';
import '../../../domain/entities/hex_tile.dart';
import '../../providers/app_providers.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _hexSourceId = 'hex_source';
  static const _hexFillLayerId = 'hex_fill_layer';
  static const _hexLineLayerId = 'hex_line_layer';

  final H3 _h3 = const H3Factory().load();

  MapboxMap? _mapboxMap;
  StreamSubscription<geolocator.Position>? _positionSubscription;
  geolocator.Position? _currentPosition;
  String? _currentH3Index;
  bool _styleReady = false;
  bool _cameraInitialized = false;
  bool _tapInteractionInstalled = false;

  BannerAd? _bannerAd;
  bool _bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
    _initBannerAd();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
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

    _positionSubscription = geolocator.Geolocator.getPositionStream(
      locationSettings: const geolocator.LocationSettings(
        accuracy: geolocator.LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(_onNewPosition);
  }

  void _onNewPosition(geolocator.Position position) {
    final h3Index = _toH3IndexString(position.latitude, position.longitude);

    if (mounted) {
      setState(() {
        _currentPosition = position;
        _currentH3Index = h3Index;
      });
    }

    _refreshHexSource();
    _updateGpsPuck();
    _setInitialCameraIfPossible();
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

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: hexesAsync.when(
              data: (hexes) => MapWidget(
                key: const ValueKey('terrango_mapbox'),
                styleUri: config.mapDarkStyleUri,
                viewport: CameraViewportState(
                  zoom: config.mapDefaultZoom,
                  center: _initialCenterFromState(hexes),
                ),
                onMapCreated: (mapboxMap) async {
                  _mapboxMap = mapboxMap;
                  if (!_tapInteractionInstalled) {
                    _tapInteractionInstalled = true;
                    mapboxMap.addInteraction(
                      TapInteraction.onMap((gestureContext) {
                        if (gestureContext.gestureState != GestureState.ended) {
                          return;
                        }
                        final tappedH3 = _toH3IndexString(
                          gestureContext.point.coordinates.lat.toDouble(),
                          gestureContext.point.coordinates.lng.toDouble(),
                        );
                        final tappedHex = _findHexByH3Index(hexes, tappedH3);
                        if (tappedHex != null && mounted) {
                          _openHexContextSheet(context, tappedHex, hexes);
                        }
                      }),
                      interactionID: 'hex-map-tap',
                    );
                  }
                },
                onStyleLoadedListener: (_) async {
                  _styleReady = true;
                  await _ensureGameLayers();
                  _refreshHexSource();
                  _updateGpsPuck();
                  _setInitialCameraIfPossible();
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Nepodarilo se nacist mapu: $error'),
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
              const Row(
                children: [
                  Expanded(child: _QuickActionButton(label: 'RECRUITMENT')),
                  SizedBox(width: 8),
                  Expanded(child: _QuickActionButton(label: 'BARRACKS')),
                  SizedBox(width: 8),
                  Expanded(child: _QuickActionButton(label: 'BASES')),
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
                const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
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
    if (_currentPosition != null) {
      return Point(
        coordinates: Position(
          _currentPosition!.longitude,
          _currentPosition!.latitude,
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
        data: jsonEncode(_buildHexFeatureCollection(ref.read(visibleHexesProvider).value ?? const [])),
      ),
    );

    await map.style.addLayer(
      FillLayer(
        id: _hexFillLayerId,
        sourceId: _hexSourceId,
        fillOpacity: 0.4,
        fillColorExpression: [
          'match',
          ['get', 'state'],
          'owned',
          '#2196F3',
          'enemy',
          '#E53935',
          '#9E9E9E',
        ],
      ),
    );

    await map.style.addLayer(
      LineLayer(
        id: _hexLineLayerId,
        sourceId: _hexSourceId,
        lineOpacity: 0.95,
        lineColorExpression: [
          'case',
          ['==', ['get', 'isCurrent'], true],
          '#FFD54F',
          ['==', ['get', 'state'], 'owned'],
          '#64B5F6',
          ['==', ['get', 'state'], 'enemy'],
          '#EF9A9A',
          '#BDBDBD',
        ],
        lineWidthExpression: [
          'case',
          ['==', ['get', 'isCurrent'], true],
          3.4,
          1.2,
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
      await source.updateGeoJSON(jsonEncode(_buildHexFeatureCollection(hexes)));
    }
  }

  Map<String, dynamic> _buildHexFeatureCollection(List<HexTile> hexes) {
    final features = <Map<String, dynamic>>[];

    for (final hex in hexes) {
      final h3Index = _parseH3(hex.h3Index);
      final boundary = _h3.h3ToGeoBoundary(h3Index);
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
          'isCurrent': hex.h3Index == _currentH3Index,
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
    final position = _currentPosition;
    if (map == null || !_styleReady || position == null) {
      return;
    }

    _cameraInitialized = true;
    await map.setCamera(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: ref.read(appConfigProvider).mapDefaultZoom,
      ),
    );
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
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _HexContextSheet(
            hex: hex,
            allHexes: allHexes,
            currentH3Index: _currentH3Index,
            neighborBonusPercent: _neighborBonusPercent(hex, allHexes),
            onOccupyPressed: () => _occupyHex(hex),
            onSetCenterChanged: (value) => _setCenter(hex, value),
            onDeployPressed: () => _sendGarrisonModify(hex: hex, action: 'DEPLOY'),
            onWithdrawPressed: () => _sendGarrisonModify(hex: hex, action: 'WITHDRAW'),
            onSendReinforcementBurnPressed: () => _sendReinforcements(
              hex: hex,
              burnSupportCount: 1,
            ),
            onSendReinforcementLossyPressed: () => _sendReinforcements(
              hex: hex,
              burnSupportCount: null,
            ),
            onScoutPressed: () => _scoutHex(hex),
            onAttackPressed: () => _attackHex(hex),
          ),
        );
      },
    );
  }

  Future<void> _occupyHex(HexTile hex) async {
    if (_currentPosition == null) {
      _showInfo('Nejdriv pockej na GPS polohu.');
      return;
    }

    try {
      await ref
          .read(gameApiDataSourceProvider)
          .occupyHex(
            h3Index: hex.h3Index,
            latitude: _currentPosition!.latitude,
            longitude: _currentPosition!.longitude,
          );
      _showInfo('Pozadavek na obsazeni byl odeslan.');
      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(visibleHexesProvider);
    } catch (error) {
      _showInfo('Obsazeni selhalo: $error');
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
        _showInfo('Nelze urcit territoryId pro zmenu centra.');
        return;
      }

      await ref
          .read(gameApiDataSourceProvider)
          .setTerritoryCenter(territoryId: territoryId, h3Index: hex.h3Index);
      _showInfo('Center bylo zmeneno.');
      ref.invalidate(visibleHexesProvider);
    } catch (error) {
      _showInfo('Zmena centra selhala: $error');
    }
  }

  Future<void> _sendGarrisonModify(
    {
    required HexTile hex,
    required String action,
  }) async {
    final socket = ref.read(gameSocketDataSourceProvider);
    socket.sendJson({
      'event': 'garrison_modify',
      'h3Index': hex.h3Index,
      'action': action,
      'composition': [
        {
          'type': 'WARRIOR',
          'rarity': 'STANDARD',
          'skill': null,
          'count': 1,
          'totalBs': 100,
        },
      ],
    });
    _showInfo('Akce $action byla odeslana.');
  }

  Future<void> _sendReinforcements(
    {
    required HexTile hex,
    required int? burnSupportCount,
  }) async {
    final socket = ref.read(gameSocketDataSourceProvider);
    socket.sendJson({
      'event': 'send_reinforcements',
      'targetH3Index': hex.h3Index,
      'composition': [
        {
          'type': 'WARRIOR',
          'rarity': 'STANDARD',
          'skill': null,
          'count': 2,
          'totalBs': 200,
        },
      ],
      'burnSupportCount': burnSupportCount,
    });

    _showInfo(
      burnSupportCount == null
          ? 'Posily odeslany s transit ztratami.'
          : 'Posily odeslany se spaleni SUPPORT.',
    );
  }

  Future<void> _scoutHex(HexTile hex) async {
    final socket = ref.read(gameSocketDataSourceProvider);
    socket.sendJson({'event': 'scout_hex', 'targetH3Index': hex.h3Index});
    _showInfo('Scout akce odeslana.');
  }

  Future<void> _attackHex(HexTile hex) async {
    final socket = ref.read(gameSocketDataSourceProvider);
    socket.sendJson({
      'event': 'attack_hex',
      'targetH3Index': hex.h3Index,
      'attackerComposition': [
        {
          'type': 'WARRIOR',
          'rarity': 'STANDARD',
          'skill': null,
          'count': 2,
          'totalBs': 200,
        },
      ],
    });
    _showInfo('Utok byl odeslan.');
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int _neighborBonusPercent(HexTile target, List<HexTile> allHexes) {
    if (target.state != HexState.owned) {
      return 0;
    }

    final owned = <String>{
      for (final hex in allHexes)
        if (hex.state == HexState.owned) hex.h3Index,
    };

    final neighbors = _h3.kRing(_parseH3(target.h3Index), 1);
    var count = 0;
    for (final neighbor in neighbors) {
      final neighborString = neighbor.toRadixString(16);
      if (neighborString != target.h3Index && owned.contains(neighborString)) {
        count += 1;
      }
    }

    return count * 100;
  }

  BigInt _parseH3(String h3Index) => BigInt.parse(h3Index, radix: 16);

  String _toH3IndexString(double lat, double lon) {
    final h3Index = _h3.geoToH3(GeoCoord(lat: lat, lon: lon), 9);
    return h3Index.toRadixString(16);
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
  const _QuickActionButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: () {}, child: Text(label));
  }
}

class _HexContextSheet extends StatelessWidget {
  const _HexContextSheet({
    required this.hex,
    required this.allHexes,
    required this.currentH3Index,
    required this.neighborBonusPercent,
    required this.onOccupyPressed,
    required this.onSetCenterChanged,
    required this.onDeployPressed,
    required this.onWithdrawPressed,
    required this.onSendReinforcementBurnPressed,
    required this.onSendReinforcementLossyPressed,
    required this.onScoutPressed,
    required this.onAttackPressed,
  });

  final HexTile hex;
  final List<HexTile> allHexes;
  final String? currentH3Index;
  final int neighborBonusPercent;
  final VoidCallback onOccupyPressed;
  final ValueChanged<bool> onSetCenterChanged;
  final VoidCallback onDeployPressed;
  final VoidCallback onWithdrawPressed;
  final VoidCallback onSendReinforcementBurnPressed;
  final VoidCallback onSendReinforcementLossyPressed;
  final VoidCallback onScoutPressed;
  final VoidCallback onAttackPressed;

  bool get _isStandingInHex => currentH3Index == hex.h3Index;

  @override
  Widget build(BuildContext context) {
    final title = switch (hex.state) {
      HexState.free => 'Volny hex',
      HexState.owned => 'Tvuj hex',
      HexState.enemy => 'Nepratelsky hex',
    };

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(hex.h3Index, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (hex.state == HexState.free) ...[
            const Text('Tento hex je volny a lze ho okamzite obsadit.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOccupyPressed,
              icon: const Icon(Icons.flag),
              label: const Text('Obsadit uzemi'),
            ),
          ],
          if (hex.state == HexState.owned) ...[
            Text('Nazev uzemi: ${hex.isCenter ? "Domovska zakladna" : "Outpost"}'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.workspace_premium_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Nastavit jako Center 👑')),
                Switch(value: hex.isCenter, onChanged: onSetCenterChanged),
              ],
            ),
            const SizedBox(height: 8),
            Text('Background Bonus: +$neighborBonusPercent%'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: onDeployPressed,
                  child: const Text('Posilit posadku'),
                ),
                FilledButton.tonal(
                  onPressed: onWithdrawPressed,
                  child: const Text('Stahnout do rezervy'),
                ),
                FilledButton.tonal(
                  onPressed: onSendReinforcementBurnPressed,
                  child: const Text('Outpost: spal 1 📡, bez ztrat'),
                ),
                FilledButton.tonal(
                  onPressed: onSendReinforcementLossyPressed,
                  child: const Text('Outpost: poslat s -40% ztratou'),
                ),
              ],
            ),
          ],
          if (hex.state == HexState.enemy) ...[
            Text('Vlastnik: ${hex.ownerName ?? 'Neznamy'}'),
            const SizedBox(height: 8),
            const Text('Fog of war: ??? BS'),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: onScoutPressed,
                  child: const Text('Scout'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isStandingInHex ? onAttackPressed : null,
                  child: const Text('ATTACK!'),
                ),
              ],
            ),
            if (!_isStandingInHex) ...[
              const SizedBox(height: 8),
              const Text('Pro utok musis fyzicky stat v tomto hexu.'),
            ],
          ],
        ],
      ),
    );
  }
}

