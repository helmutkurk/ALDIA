import 'package:latlong2/latlong.dart';

/// Build-time configuration. Override with `--dart-define=API_BASE_URL=...`.
class AppConfig {
  const AppConfig._();

  /// Android emulator reaches the host machine at 10.0.2.2.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );

  /// Citizens log in with their phone at app start. Set
  /// REQUIRE_CITIZEN_LOGIN=false only for anonymous demos.
  static const bool requireCitizenLogin = bool.fromEnvironment(
    'REQUIRE_CITIZEN_LOGIN',
    defaultValue: true,
  );

  /// MVP only: the login screen offers a local test account. Build with
  /// ALLOW_TEST_ACCOUNT=false once the real login method is decided.
  static const bool allowTestAccount = bool.fromEnvironment(
    'ALLOW_TEST_ACCOUNT',
    defaultValue: true,
  );

  /// Default map view: Guatemala City.
  static const LatLng defaultCenter = LatLng(14.6349, -90.5069);
  static const double defaultZoom = 13;

  /// Public OSM tiles are for light use only (OSM tile usage policy). For
  /// production set TILE_URL to a provider with an agreement or your own server.
  static const String tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const String userAgentPackage = 'org.aldia.aldia_app';

  static const Duration requestTimeout = Duration(seconds: 20);
  static const int maxNoteLength = 280;
}
