import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/repositories/map_repository_impl.dart';
import '../../domain/entities/hex_tile.dart';
import '../../domain/repositories/map_repository.dart';
import '../../domain/usecases/get_visible_hexes_use_case.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final mapRepositoryProvider = Provider<MapRepository>((ref) {
  return MapRepositoryImpl();
});

final getVisibleHexesUseCaseProvider = Provider<GetVisibleHexesUseCase>((ref) {
  final repository = ref.watch(mapRepositoryProvider);
  return GetVisibleHexesUseCase(repository);
});

final visibleHexesProvider = FutureProvider<List<HexTile>>((ref) {
  final useCase = ref.watch(getVisibleHexesUseCaseProvider);
  return useCase();
});

final nicknameProvider = StateProvider<String>((ref) => '');
