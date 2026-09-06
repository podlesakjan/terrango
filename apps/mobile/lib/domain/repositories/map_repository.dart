import '../entities/hex_tile.dart';

abstract class MapRepository {
  Future<List<HexTile>> getVisibleHexes();

  Stream<List<HexTile>> watchVisibleHexes();

  /// Keeps only cells in the active map viewport. Updates for cells outside
  /// this set are discarded, including late socket responses from an old view.
  void setVisibleH3Indexes(Iterable<String> h3Indexes);

  void applyMapSnapshot(Map<String, dynamic> payload);

  void applyMapGridUpdate(Map<String, dynamic> payload);

  void applyHexDetailUpdate(Map<String, dynamic> payload);
}
