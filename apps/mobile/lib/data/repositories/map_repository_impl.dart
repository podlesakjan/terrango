import 'dart:async';

import '../../domain/entities/hex_tile.dart';
import '../../domain/repositories/map_repository.dart';

class MapRepositoryImpl implements MapRepository {
  MapRepositoryImpl() {
    _emitCurrent();
  }

  final StreamController<List<HexTile>> _controller =
      StreamController<List<HexTile>>.broadcast();
  final Map<String, HexTile> _visibleHexesByIndex = <String, HexTile>{};

  @override
  Future<List<HexTile>> getVisibleHexes() async {
    return _sortedVisibleHexes();
  }

  @override
  Stream<List<HexTile>> watchVisibleHexes() {
    return _watchVisibleHexes();
  }

  @override
  void applyMapSnapshot(Map<String, dynamic> payload) {
    final hexagons = payload['hexagons'];
    if (hexagons is! List) {
      return;
    }

    _replaceVisibleHexes(
      hexagons.whereType<Map<String, dynamic>>().map(HexTile.fromGridPayload),
    );
  }

  @override
  void applyMapGridUpdate(Map<String, dynamic> payload) {
    final hexagons = payload['hexagons'];
    if (hexagons is! List) {
      return;
    }

    for (final hex in hexagons.whereType<Map<String, dynamic>>()) {
      final tile = HexTile.fromGridPayload(hex);
      if (tile.h3Index.isEmpty) {
        continue;
      }
      _visibleHexesByIndex[tile.h3Index] = tile;
    }
    _emitCurrent();
  }

  @override
  void applyHexDetailUpdate(Map<String, dynamic> payload) {
    final tile = HexTile.fromDetailPayload(payload);
    if (tile.h3Index.isEmpty) {
      return;
    }

    final existing = _visibleHexesByIndex[tile.h3Index];
    _visibleHexesByIndex[tile.h3Index] = existing == null ? tile : existing.copyWith(
      state: tile.state,
      ownerName: tile.ownerName ?? existing.ownerName,
      hasGarrison: tile.hasGarrison,
      isCenter: tile.isCenter,
      territoryName: tile.territoryName ?? existing.territoryName,
      backgroundBonusPercent: tile.backgroundBonusPercent ?? existing.backgroundBonusPercent,
    );
    _emitCurrent();
  }

  void _replaceVisibleHexes(Iterable<HexTile> tiles) {
    _visibleHexesByIndex
      ..clear()
      ..addEntries(tiles.where((tile) => tile.h3Index.isNotEmpty).map((tile) => MapEntry(tile.h3Index, tile)));
    _emitCurrent();
  }

  List<HexTile> _sortedVisibleHexes() {
    final tiles = _visibleHexesByIndex.values.toList(growable: false);
    tiles.sort((a, b) => a.h3Index.compareTo(b.h3Index));
    return List<HexTile>.unmodifiable(tiles);
  }

  void _emitCurrent() {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(_sortedVisibleHexes());
  }

  void dispose() {
    _controller.close();
  }

  Stream<List<HexTile>> _watchVisibleHexes() async* {
    yield _sortedVisibleHexes();
    await for (final tiles in _controller.stream) {
      yield tiles;
    }
  }
}
