const _hostedApiBaseUrl = 'https://jojomusicapi.jojoserv.com';
const _convexDeploymentUrl = 'https://convex.jojoserv.com';
const _convexSiteUrl = 'https://convex-site.jojoserv.com';

class AppEnvironment {
  const AppEnvironment({
    required this.apiBaseUrl,
    required this.convexUrl,
    required this.convexSiteUrl,
  });

  final String apiBaseUrl;
  final String convexUrl;
  final String convexSiteUrl;

  String get resolveUrl => '$apiBaseUrl/api/v1/tracks/resolve';

  static AppEnvironment fromPlatform() {
    const apiOverride = String.fromEnvironment('API_BASE_URL');
    const convexOverride = String.fromEnvironment('CONVEX_URL');
    const convexSiteOverride = String.fromEnvironment('CONVEX_SITE_URL');
    return AppEnvironment(
      apiBaseUrl: apiOverride.isNotEmpty ? apiOverride : _hostedApiBaseUrl,
      convexUrl: convexOverride.isNotEmpty ? convexOverride : _convexDeploymentUrl,
      convexSiteUrl: convexSiteOverride.isNotEmpty ? convexSiteOverride : _convexSiteUrl,
    );
  }
}
