import '../entities/hex_tile.dart';
import '../repositories/map_repository.dart';

class GetVisibleHexesUseCase {
  const GetVisibleHexesUseCase(this._mapRepository);

  final MapRepository _mapRepository;

  Future<List<HexTile>> call() {
    return _mapRepository.getVisibleHexes();
  }
}
