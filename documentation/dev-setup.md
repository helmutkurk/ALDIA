# Development setup

Versions are pinned in `.mise.toml` (Node 24, Python 3.12, uv, Flutter 3.47.9). Install [mise](https://mise.jdx.dev),
then in the repo root:

```bash
mise install            # installs the pinned toolchains
bash scripts/install-githooks.sh
```

## Run everything with Docker

```bash
cp .env.example .env    # set POSTGRES_PASSWORD; local only, never committed
make up                 # db, verifier, api, portal
make logs
make down
```

- Portal: http://localhost:8080 (container) or http://localhost:5173 (`make portal-dev`)
- API docs: http://localhost:8000/docs
- The verifier is internal (`verifier:8001`); it only runs in `stub` mode until a model is plugged in.

## Without Docker

Run from the repository root on Linux with Bash, Python 3, curl, make, `setsid`, `flock` and `timeout` available,
plus the pinned uv and Node toolchains:

```bash
make dev-all             # foreground; Ctrl-C stops all children
```

The launcher synchronizes the existing pinned Python dependencies with `uv sync --frozen`, installs the existing
portal lockfile with `npm ci` if `node_modules/` is absent, starts the stub verifier, applies Alembic migrations,
starts the API and portal, waits for their health endpoints (including the portal API proxy), then runs `make seed`.
If dependencies are already present but stale, run `cd portal && npm ci` before starting again.

| Service | URL |
|---|---|
| Portal | http://localhost:5173 |
| API health / docs | http://localhost:8000/api/health / http://localhost:8000/docs |
| Verifier health | http://localhost:8001/health |

Services bind to `127.0.0.1`. No Docker or environment files are used: the launcher supplies local configuration,
and Vite's `local-stack` mode disables environment-file loading. SQLite lives in `.local/aldia.db`, photos in
`.local/photos/`, and per-service, setup, migration and seed logs in `.local/logs/`. All of `.local/` is git-ignored,
including `.local/shots/`. The lock and command pipe in `.local/` let another terminal control the supervisor without
signalling unrelated processes. An occupied port causes startup to fail with an explanation.

```bash
make dev-status          # supervisor ownership + health of all three; nonzero on failure
make dev-stop            # stops the owned stack, including its child process groups
```

Starting again while the stack is healthy returns its status and starts no extra processes. Restarting preserves the
database and idempotent demo seed. Failed startup or an exited service stops the remaining children. For a fresh demo,
stop the stack and remove `.local/aldia.db` and `.local/photos/` only if their local synthetic data is disposable.
Independent `make seed` calls still use the defaults described in [testing.md](testing.md); to target this stack:

```bash
DATABASE_URL="sqlite:///$(pwd)/.local/aldia.db" PHOTO_DIR="$(pwd)/.local/photos" make seed
```

### Real-request smoke test

```bash
make dev-stop
make dev-all SMOKE=1      # equivalent to bash scripts/dev-local.sh --smoke
```

The launcher still generates legacy `STAFF_TOKEN` and `SUPERVISOR_TOKEN` values for its smoke child.
**v0.4 change:** those headers are disabled unless the API receives both `ENV=dev` and
`AUTH_DEV_TOKENS=true`. The existing smoke script tests this development compatibility path,
not account login; it needs these explicit flags. Updating the root launcher/smoke scripts is
outside the staff-auth change's permitted folders. Normal staff access uses accounts below.
Do not capture initial demo passwords in the launcher's seed log: create the accounts first
in a private terminal against its database, or use the manual API workflow below.

The test uses real curl requests and Pillow from the existing API environment. It generates a 1280x960 JPEG with
EXIF GPS, creates a report and retries its idempotency key (`201`, then identical `200`, only one new report), checks
the served JPEG has no EXIF/GPS, exercises categories, list, both nearby routes, clusters, stats and CSV with UTF-8
BOM, and checks unauthenticated/illegal/legal staff transitions (`401`/`409`/`200`) plus the public timeline event.
It also checks verifier/API health and portal HTML/proxy health. Each smoke run adds one synthetic `[smoke]` report;
temporary images and response files are removed, and its result is saved in `.local/logs/smoke.log`.
The stack stays up after success and stops on smoke failure; inspect the smoke log on failure.

### Browser capture (outside the Codex sandbox)

The capture helper requires an already installed Playwright module and Chromium runtime. It adds no dependencies.
With the stack running, execute outside the sandbox:

```bash
node scripts/screenshot-local.mjs
# If Playwright is installed elsewhere:
PLAYWRIGHT_MODULE=/absolute/path/to/playwright node scripts/screenshot-local.mjs
```

It waits for the Leaflet map, a map marker/cluster and a report list item, then saves `.local/shots/portal.png`.
The 2026-11-19 sandbox run verified HTTP only: no browser host was available, Playwright was not installed in the repo,
and launching Chromium inside this sandbox is prohibited. Map rendering, tiles and the screenshot remain unverified.

### Staff accounts (v0.4 quick start)

For a local HTTP demo, start the verifier as above and run these commands from `backend/api/`
in a private terminal. Use a database separate from the managed stack unless deliberately
pointing both at the same paths:

```bash
uv sync --frozen
export ENV=dev DATABASE_URL=sqlite:///./aldia.db PHOTO_DIR=/tmp/aldia-api-photos
export VERIFIER_URL=http://127.0.0.1:8001
uv run alembic upgrade head
uv run python -m app.cli create-admin --username admin
uv run python scripts/seed_demo.py
uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --no-access-log
```

The CLI asks for a password without echo (12–1024 characters), or reads one line from stdin
when piped from a secret manager. The seed prints a random initial password once for each
new `operador`/`supervisor` account; do not redirect this output to shared logs. Start the
portal with `cd portal && npm run dev` in another terminal. Open **Modo personal**, log in,
and use **Cerrar sesión** when finished. Admin user management is available through the API.
There are no fixed demo passwords: [demo-credentials.md](demo-credentials.md).

Leave `AUTH_DEV_TOKENS` unset for normal development. Set it to `true` only to test the old
panel alongside `ENV=dev`; `/api/auth/config` must report `dev_tokens: true` for it to appear.
Every fallback attempt logs a warning without the header value. Production defaults to
`ENV=production`, Secure cookies and disabled fallback; use HTTPS. Portal and API should share
an origin through `/api` so JavaScript can read the CSRF cookie. Authenticated writes echo it
as `X-CSRF-Token`. See [staff-auth.md](decisions/staff-auth.md) for limits and operations.

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

The camera is not available in the iOS simulator and the app takes live photos only (no gallery fallback), so the photo
step needs a real phone. Test steps, demo data and QA scripts: [testing.md](testing.md).

### Checks before every push

```bash
make check              # api, verifier, portal and app: lint + tests (+ build for the portal)
```

Demo data: `make seed` creates synthetic reports (see [testing.md](testing.md), section 2.4).

## Tests per area

| Area | Command (from the folder) |
|---|---|
| `backend/api`, `backend/verifier` | `make test` (uses `uv run pytest`) |
| `portal` | `npm run check` |
| `app` | `flutter analyze && flutter test` |
