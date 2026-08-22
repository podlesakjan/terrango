import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geolocator;

class LocationState {
  const LocationState({this.position, this.h3Index});

  final geolocator.Position? position;
  final String? h3Index;
}

class LocationNotifier extends StateNotifier<LocationState> {
  LocationNotifier() : super(const LocationState());

  void updateLocation(geolocator.Position position, String h3Index) {
    state = LocationState(position: position, h3Index: h3Index);
  }
}

final locationProvider = StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  return LocationNotifier();
});
