class AppConfig {
  /// Sem napiš adresu serveru, např. `https://api.terrango.com` nebo `http://10.0.2.2:3000`.
  static const String serverBaseUrl = 'http://10.0.2.2:3000';

  /// Sem napiš Mapbox public token.
  static const String mapboxAccessToken = 'PASTE_MAPBOX_ACCESS_TOKEN_HERE';

  static String get apiBaseUrl => '$serverBaseUrl/api/v1';
  static Uri get apiBaseUri => Uri.parse(apiBaseUrl);
  static Uri get webSocketUri => Uri.parse(serverBaseUrl.replaceFirst('http', 'ws'));

  static bool get hasMapboxToken => mapboxAccessToken.isNotEmpty && mapboxAccessToken != 'PASTE_MAPBOX_ACCESS_TOKEN_HERE';
}

