import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.websocketUrl,
    required this.mapDefaultZoom,
    required this.mapboxAccessToken,
    required this.mapDarkStyleUri,
    required this.admobBannerAndroidUnitId,
    required this.admobBannerIosUnitId,
    required this.apiBearerToken,
  });

  final String apiBaseUrl;
  final String websocketUrl;
  final double mapDefaultZoom;
  final String mapboxAccessToken;
  final String mapDarkStyleUri;
  final String admobBannerAndroidUnitId;
  final String admobBannerIosUnitId;
  final String apiBearerToken;

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      apiBaseUrl: dotenv.env['API_BASE_URL'] ?? 'https://terrango.onrender.com/api/v1',
      websocketUrl: dotenv.env['WEBSOCKET_URL'] ?? 'wss://terrango.onrender.com',
      mapDefaultZoom: double.tryParse(dotenv.env['MAP_DEFAULT_ZOOM'] ?? '14.0') ?? 14.0,
      mapboxAccessToken: dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '',
      mapDarkStyleUri: dotenv.env['MAPBOX_DARK_STYLE_URI'] ?? 'mapbox://styles/mapbox/dark-v11',
      admobBannerAndroidUnitId: dotenv.env['ADMOB_BANNER_ANDROID_UNIT_ID'] ?? 'ca-app-pub-3940256099942544/6300978111',
      admobBannerIosUnitId: dotenv.env['ADMOB_BANNER_IOS_UNIT_ID'] ?? 'ca-app-pub-3940256099942544/2934735716',
      apiBearerToken: dotenv.env['API_BEARER_TOKEN'] ?? '',
    );
  }
}
