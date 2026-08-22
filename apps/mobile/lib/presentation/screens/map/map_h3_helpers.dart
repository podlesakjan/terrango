import 'package:flutter/foundation.dart';
import 'package:h3_flutter/h3_flutter.dart';

class MapH3Calculations {
  static String _geoToH3(Map<String, double> params) {
    final h3 = const H3Factory().load();
    final lat = params['lat']!;
    final lon = params['lon']!;
    final h3Index = h3.geoToH3(GeoCoord(lat: lat, lon: lon), 9);
    return h3Index.toRadixString(16);
  }

  static Future<String> geoToH3(double lat, double lon) {
    return compute(_geoToH3, {'lat': lat, 'lon': lon});
  }

  static Set<String> _kRing(Map<String, dynamic> params) {
    final h3 = const H3Factory().load();
    final h3Index = params['h3Index'] as String;
    final radius = params['radius'] as int;
    return h3
        .kRing(BigInt.parse(h3Index, radix: 16), radius)
        .map((index) => index.toRadixString(16))
        .toSet();
  }

  static Future<Set<String>> kRing(String h3Index, int radius) {
    return compute(_kRing, {'h3Index': h3Index, 'radius': radius});
  }
}
