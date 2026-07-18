import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../config/app_config.dart';
import '../map/h3_map_helpers.dart';
import '../models/game_models.dart';
import '../state/game_session_controller.dart';
import '../screens/hex_context_sheet.dart';

class MapboxHexMap extends StatefulWidget {
  const MapboxHexMap({
    super.key,
    required this.controller,
    required this.onNavigateToRecruitment,
  });

  final GameSessionController controller;
  final VoidCallback onNavigateToRecruitment;

  @override
  State<MapboxHexMap> createState() => _MapboxHexMapState();
}

class _MapboxHexMapState extends State<MapboxHexMap> {
  static const _sourceId = 'terrango-hexes-source';
  static const _fillLayerId = 'terrango-hexes-fill';
  static const _lineLayerId = 'terrango-hexes-line';

  MapboxMap? _mapboxMap;
  bool _styleLoaded = false;
  String? _lastGeoJson;

  @override
  void initState() {
    super.initState();
    if (AppConfig.hasMapboxToken) {
      MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final hexes = controller.visibleHexes
        .map((tile) => BigInt.tryParse(tile.h3Index))
        .whereType<BigInt>()
        .toList(growable: false);

    final geoJson = hexes.isEmpty
        ? null
        : H3MapHelpers.instance.featureCollectionForHexes(
            hexes,
            properties: (index) {
              final tile = controller.visibleHexes.firstWhere(
                (item) => BigInt.tryParse(item.h3Index) == index,
                orElse: () => controller.visibleHexes.first,
              );
              return {
                'h3Index': tile.h3Index,
                'state': tile.state.name,
                'ownerName': tile.ownerName,
                'hasGarrison': tile.hasGarrison,
                'isCenter': tile.isCenter,
                'color': tile.color?.value ?? 0,
              };
            },
          );

    if (_styleLoaded && _mapboxMap != null && geoJson != null && geoJson != _lastGeoJson) {
      _lastGeoJson = geoJson;
      unawaited(_pushHexGeoJson(geoJson));
    }

    if (!AppConfig.hasMapboxToken) {
      return _FallbackMap(controller: controller, onHexTap: _openHexSheet);
    }

    return MapWidget(
      key: const ValueKey('terrango-mapbox-map'),
      styleUri: MapboxStyles.DARK,
      androidHostingMode: AndroidPlatformViewHostingMode.VD,
      viewport: CameraViewportState(
        center: Point(coordinates: Position(14.4378, 50.0755)),
        zoom: 12.0,
        pitch: 0.0,
      ),
      onMapCreated: (mapboxMap) {
        _mapboxMap = mapboxMap;
      },
      onStyleLoadedListener: (_) async {
        _styleLoaded = true;
        if (geoJson != null) {
          await _pushHexGeoJson(geoJson);
        }
      },
      onTapListener: (_) => _openHexSheet(controller.detailFor(controller.currentLocationH3Index)),
    );
  }

  Future<void> _pushHexGeoJson(String geoJson) async {
    final map = _mapboxMap;
    if (map == null) return;

    final source = GeoJsonSource(id: _sourceId, data: geoJson, generateId: true, lineMetrics: true);
    try {
      await map.style.addSource(source);
    } catch (_) {
      try {
        final existing = await map.style.getSource(_sourceId);
        if (existing is GeoJsonSource) {
          await existing.updateGeoJSON(geoJson);
        }
      } catch (_) {}
    }

    try {
      await map.style.addLayer(
        FillLayer(
          id: _fillLayerId,
          sourceId: _sourceId,
          fillColor: 0xFF4FC3F7,
          fillOpacity: 0.24,
          fillOutlineColor: 0xFF8FB7FF,
        ),
      );
    } catch (_) {}

    try {
      await map.style.addLayer(
        LineLayer(
          id: _lineLayerId,
          sourceId: _sourceId,
          lineColor: 0xFF8FB7FF,
          lineWidth: 2.0,
          lineOpacity: 0.9,
        ),
      );
    } catch (_) {}
  }

  Future<void> _openHexSheet(HexDetail hex) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HexContextSheet(hexDetail: hex),
    );
  }
}

class _FallbackMap extends StatelessWidget {
  const _FallbackMap({required this.controller, required this.onHexTap});

  final GameSessionController controller;
  final Future<void> Function(HexDetail hex) onHexTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.all(16),
      childAspectRatio: 0.92,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final tile in controller.visibleHexes)
          GestureDetector(
            onTap: () => onHexTap(controller.detailFor(tile.h3Index)),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: tile.color?.withValues(alpha: 0.24) ?? Colors.white10,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: tile.isCenter ? 0.35 : 0.12), width: tile.isCenter ? 2 : 1),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tile.state == HexOwnershipState.owned ? Icons.shield_rounded : tile.state == HexOwnershipState.enemy ? Icons.warning_rounded : Icons.hexagon_rounded),
                    const SizedBox(height: 6),
                    Text(tile.h3Index.substring(tile.h3Index.length - 5), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}


