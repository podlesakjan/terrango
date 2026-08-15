import '../entities/hex_tile.dart';

abstract class MapRepository {
  Future<List<HexTile>> getVisibleHexes();

  Stream<List<HexTile>> watchVisibleHexes();

  void applyMapSnapshot(Map<String, dynamic> payload);

  void applyMapGridUpdate(Map<String, dynamic> payload);

  void applyHexDetailUpdate(Map<String, dynamic> payload);
}
