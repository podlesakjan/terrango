import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:h3_flutter/h3_flutter.dart';
import 'package:h3_common/h3_common.dart';
import 'package:geojson2h3/geojson2h3.dart';

class H3MapHelpers {
  H3MapHelpers._(this._h3);

  final H3 _h3;

  static final H3MapHelpers instance = H3MapHelpers._(const H3Factory().load());

  static const int mapResolution = 9;

  BigInt h3FromLatLng({required double latitude, required double longitude, int resolution = mapResolution}) {
    return _h3.geoToCell(GeoCoord(lat: latitude, lon: longitude), resolution);
  }

  List<GeoCoord> boundaryFor(BigInt h3Index) {
    return _h3.cellToBoundary(h3Index);
  }

  List<BigInt> ringFor(BigInt center, {int radius = 1}) {
    return _h3.gridDisk(center, radius);
  }

  String featureCollectionForHexes(List<BigInt> hexes, {Map? Function(BigInt index)? properties}) {
    final geojson = Geojson2H3(_h3).h3SetToFeatureCollection(hexes, properties: properties);
    return jsonEncode(geojson);
  }

  String featureForHex(BigInt h3Index, {Map? properties}) {
    return jsonEncode(Geojson2H3(_h3).h3ToFeature(h3Index, properties: properties));
  }

  List<List<double>> boundaryToLonLatList(BigInt h3Index) {
    final boundary = boundaryFor(h3Index);
    return [
      for (final coord in boundary) [coord.lon, coord.lat],
      [boundary.first.lon, boundary.first.lat],
    ];
  }
}

