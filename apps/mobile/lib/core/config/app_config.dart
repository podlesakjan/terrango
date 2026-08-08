class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.websocketUrl,
    required this.mapDefaultZoom,
  });

  final String apiBaseUrl;
  final String websocketUrl;
  final double mapDefaultZoom;

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:3000/api/v1',
      ),
      websocketUrl: const String.fromEnvironment(
        'WEBSOCKET_URL',
        defaultValue: 'ws://localhost:3000',
      ),
      mapDefaultZoom:
          double.tryParse(
            const String.fromEnvironment(
              'MAP_DEFAULT_ZOOM',
              defaultValue: '14.0',
            ),
          ) ??
          14.0,
    );
  }
}
