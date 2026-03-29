const _hostedApiBaseUrl = 'https://jojomusicapi.jojoserv.com';

class AppEnvironment {
  const AppEnvironment({required this.apiBaseUrl});

  final String apiBaseUrl;

  String get resolveUrl => '$apiBaseUrl/api/v1/tracks/resolve';

  static AppEnvironment fromPlatform() {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      return AppEnvironment(apiBaseUrl: override);
    }
    return const AppEnvironment(apiBaseUrl: _hostedApiBaseUrl);
  }
}
