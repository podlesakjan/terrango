import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapCameraStorage {
  static const _keyPrefix = 'map_camera';
  static const _keyLat = '$_keyPrefix.lat';
  static const _keyLng = '$_keyPrefix.lng';
  static const _keyZoom = '$_keyPrefix.zoom';
  static const _keyBearing = '$_keyPrefix.bearing';
  static const _keyPitch = '$_keyPrefix.pitch';

  Future<void> save(CameraState cameraState) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLat, cameraState.center.coordinates.lat);
    await prefs.setDouble(_keyLng, cameraState.center.coordinates.lng);
    await prefs.setDouble(_keyZoom, cameraState.zoom);
    await prefs.setDouble(_keyBearing, cameraState.bearing);
    await prefs.setDouble(_keyPitch, cameraState.pitch);
  }

  Future<CameraOptions?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyLat);
    final lng = prefs.getDouble(_keyLng);
    final zoom = prefs.getDouble(_keyZoom);
    final bearing = prefs.getDouble(_keyBearing);
    final pitch = prefs.getDouble(_keyPitch);

    if (lat == null || lng == null || zoom == null) {
      return null;
    }

    return CameraOptions(
      center: Point(coordinates: Position(lng, lat)),
      zoom: zoom,
      bearing: bearing,
      pitch: pitch,
    );
  }
}
