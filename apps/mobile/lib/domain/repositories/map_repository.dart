import '../entities/hex_tile.dart';

abstract class MapRepository {
  Future<List<HexTile>> getVisibleHexes();
}
