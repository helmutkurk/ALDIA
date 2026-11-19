# Development setup

Versions are pinned in `.mise.toml` (Node 24, Python 3.12, uv, Flutter 3.47.9). Install [mise](https://mise.jdx.dev),
then in the repo root:

```bash
mise install            # installs the pinned toolchains
bash scripts/install-githooks.sh
cp .env.example .env    # local only, never committed
```

## Run everything with Docker

```bash
make up                 # db, verifier, api, portal
make logs
make down
```

- Portal: http://localhost:8080 (container) or http://localhost:5173 (`make portal-dev`)
- API docs: http://localhost:8000/docs
- The verifier is internal (`verifier:8001`); it only runs in `stub` mode until a model is plugged in.

Without Docker, run each service from its folder (see its README): `backend/api`, `backend/verifier`, `portal`.

## Mobile app (`app/`)

Owners: Fernando and Helmut. The app reads `API_BASE_URL` at build time:

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api   # Android emulator
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api  # iOS simulator
flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:8000/api  # real phone on the same Wi-Fi
```

### Android Studio (Linux, macOS, Windows)

1. Install Android Studio and, in SDK Manager, the Android SDK, Platform-Tools, Command-line Tools and one system
   image (for example API 35, x86_64).
2. Install the Flutter and Dart plugins. Point Flutter SDK to `~/.local/share/mise/installs/flutter/3.47.9`
   (path from `mise where flutter`).
3. `flutter doctor --android-licenses`, then `flutter doctor` must show no errors for Android.
4. Open the folder `app/` (not the repo root). Create an emulator in Device Manager, then pick one of the shared run
   configurations (`aldia (android emulator)`, `aldia (ios simulator)`), or run the commands above.
5. Real phone: enable developer options and USB debugging, connect, accept the prompt, run `flutter devices`.

### Xcode (macOS only)

iOS builds and the iOS simulator need a Mac with Xcode; they do not run on Linux.

1. Install Xcode from the App Store, open it once, accept the license: `sudo xcodebuild -license accept`.
2. `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` and `brew install cocoapods`.
3. `cd app && flutter pub get && cd ios && pod install`.
4. Open `app/ios/Runner.xcworkspace` (the workspace, not the project). Set your team under Signing & Capabilities
   (a free Apple ID works for the simulator and your own phone). Bundle id: `org.aldia.aldia_app` (change it once the team
   registers a real identifier).
5. Pick a simulator and press Run, or `flutter run -d <simulator id>`.

The camera is not available in the iOS simulator; use a real phone to test the live photo, or the gallery fallback in
debug builds.

### Checks before every push

```bash
make check              # api, verifier, portal and app: lint + tests (+ build for the portal)
```

## Tests per area

| Area | Command (from the folder) |
|---|---|
| `backend/api`, `backend/verifier` | `make test` (uses `uv run pytest`) |
| `portal` | `npm run check` |
| `app` | `flutter analyze && flutter test` |
