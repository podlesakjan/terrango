import '../../domain/entities/hex_tile.dart';
import '../../domain/repositories/map_repository.dart';

class MapRepositoryImpl implements MapRepository {
  @override
  Future<List<HexTile>> getVisibleHexes() async {
    // Do zacatku vracime staticky snapshot; realna data pujdou ze socketu.
    return const [
      HexTile(
        h3Index: '891f1a1c62fffff',
        state: HexState.owned,
        ownerName: 'You',
        hasGarrison: true,
        isCenter: true,
      ),
      HexTile(
        h3Index: '891f1a1c62ffffe',
        state: HexState.enemy,
        ownerName: 'Ragnarok',
        hasGarrison: true,
      ),
      HexTile(h3Index: '891f1a1c62ffffd', state: HexState.free),
    ];
  }
}
