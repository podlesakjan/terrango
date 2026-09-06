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
  Set<String> _retainedH3Indexes = <String>{};

  @override
  Future<List<HexTile>> getVisibleHexes() async {
    return _sortedVisibleHexes();
  }

  @override
  Stream<List<HexTile>> watchVisibleHexes() {
    return _watchVisibleHexes();
  }

  @override
  void setVisibleH3Indexes(Iterable<String> h3Indexes) {
    _retainedH3Indexes = h3Indexes.where((index) => index.isNotEmpty).toSet();
    final removed = _visibleHexesByIndex.keys
        .where((index) => !_retainedH3Indexes.contains(index))
        .toList(growable: false);
    if (removed.isEmpty) {
      return;
    }
    for (final index in removed) {
      _visibleHexesByIndex.remove(index);
    }
    _emitCurrent();
  }

  @override
  void applyMapSnapshot(Map<String, dynamic> payload) {
    final hexagons = payload['hexagons'];
    if (hexagons is! List) {
      return;
    }
    // A snapshot can arrive after the camera has moved. Merge its still-valid
    // cells rather than clearing cells obtained for the new viewport.
    var updated = false;
    for (final hex in hexagons.whereType<Map<String, dynamic>>()) {
      final tile = HexTile.fromGridPayload(hex);
      if (tile.h3Index.isEmpty || !_retainedH3Indexes.contains(tile.h3Index)) {
        continue;
      }
      _visibleHexesByIndex[tile.h3Index] = tile;
      updated = true;
    }
    if (updated) {
      _emitCurrent();
    }
  }

  @override
  void applyMapGridUpdate(Map<String, dynamic> payload) {
    final hexagons = payload['hexagons'];
    if (hexagons is! List) {
      return;
    }

    var updated = false;
    for (final hex in hexagons.whereType<Map<String, dynamic>>()) {
      final tile = HexTile.fromGridPayload(hex);
      if (tile.h3Index.isEmpty) {
        continue;
      }
      if (!_retainedH3Indexes.contains(tile.h3Index)) {
        continue;
      }
      _visibleHexesByIndex[tile.h3Index] = tile;
      updated = true;
    }
    if (updated) {
      _emitCurrent();
    }
  }

  @override
  void applyHexDetailUpdate(Map<String, dynamic> payload) {
    final tile = HexTile.fromDetailPayload(payload);
    if (tile.h3Index.isEmpty) {
      return;
    }
    if (!_retainedH3Indexes.contains(tile.h3Index)) {
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
