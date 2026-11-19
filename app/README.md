# app

Citizen app in Flutter / Dart (Android and iOS), Spanish (Guatemala). Product reference: SeeClickFix. It sends
photo reports of street problems to the Aldia API; the backend verifies each photo.
Contract: `../documentation/api-contract.md`. Setup for Android Studio and Xcode: `../documentation/dev-setup.md`.

## Flow

1. **Home**: map and list of nearby reports (pin color = verification status), button "Reportar", "Mis reportes".
2. **Report** in four steps: location (GPS or tap on the map), category, live photo, note. The result screen shows
   the verification checks; a rejected photo can be retaken without losing location and category.
3. **Detail**: photo, verification status, handling state (`open`, `acknowledged`, `fixed`) and checks.

## Run

```bash
mise exec -- flutter pub get
mise exec -- flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api   # Android emulator
mise exec -- flutter run --dart-define=API_BASE_URL=http://localhost:8000/api  # iOS simulator
```

Build-time options (`--dart-define`): `API_BASE_URL`, `TILE_URL` (map tiles; the public OpenStreetMap server is for
light use only, use a provider or your own tiles in production).

## Checks

```bash
mise exec -- flutter analyze
mise exec -- flutter test
```

## Layout

```
lib/
  main.dart            composition root (real services)
  app.dart             MaterialApp, providers (dependencies are injected, tests replace them)
  core/                config, theme (tokens), categories, strings (Spanish)
  data/                report model, ApiClient, ReportRepository, MyReportsStore
  services/            LocationService, PhotoService (live camera only; gallery in iOS debug)
  features/            home, report (flow controller + screens), detail, mine
  widgets/             status chips, checks list, report tile
test/                  model, API client, flow controller and widget tests (offline)
android/, ios/         platform projects (permissions: camera, location, internet)
.idea/runConfigurations/  shared Android Studio run configurations
```

## Notes

- Release builds accept only live camera photos; debug on the iOS simulator falls back to the gallery.
- Debug builds allow `http` to the local API; release builds keep cleartext traffic off (use HTTPS).
- No accounts in v0: report ids sent from this device are kept locally for "Mis reportes".
- Application id: `org.aldia.aldia_app` (change before publishing to a store).
