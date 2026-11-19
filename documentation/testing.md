# Testing guide

How to test Aldia: automated checks, running the stack, manual QA scripts for the portal, the app and the API, an
end-to-end scenario, troubleshooting and a demo checklist. Commands run from the repo root unless a `cd` says otherwise.
Install the toolchain first ([dev-setup.md](dev-setup.md)). All data in this guide is synthetic.

Verification status of this guide: the commands in sections 1 to 3 and 6 to 7 (API, seed, curl, verifier) were run on
Linux with SQLite and uvicorn, without Docker. Docker, the portal in a browser, Android and iOS steps were **not
executed** by the author; they are marked `(not executed)` and must be checked by whoever runs them first.

## 1. Automated checks

```bash
make check          # api + verifier + portal + app, same as CI
```

| Area | Command | Expected (as of 2026-11-19; counts grow) |
|---|---|---|
| API | `make api-check` (or `cd backend/api && uv run pytest`) | about 358 tests pass (354 plus 4 for the seed script), ruff and strict mypy clean |
| Verifier | `make verifier-check` | 27 tests pass |
| Portal | `make portal-check` (lint, format check, vitest, build) | about 103 tests pass, build succeeds |
| App | `make app-check` (`flutter analyze` and `flutter test`) | about 83 tests pass, no analyzer issues |

Pass criterion: exit code 0 in every area. A different number is fine if tests were added; a failure is not. Other
people may be editing a folder at the same time, so rerun before concluding that a failure is yours.

API tests use temporary SQLite databases, synthetic images and a fake verifier: they need no network and no `.env`.

## 2. Run the full stack locally

### 2.1 With Docker (`make up`) (not executed)

```bash
cp .env.example .env                       # local only, never committed
# Edit .env: set POSTGRES_PASSWORD and STAFF_TOKEN (see 2.3). Do not paste real secrets anywhere else.
make up                                    # db, verifier, api, portal
make ps                                    # all four services "running"
curl -s http://localhost:8000/api/health   # {"status":"ok"}
```

| What | URL |
|---|---|
| Portal (nginx container) | http://localhost:8080 |
| API and docs | http://localhost:8000 and http://localhost:8000/docs |
| Verifier | internal only (`verifier:8001`), not published |
| Postgres | internal only (`db:5432`) |

Ports bind to `127.0.0.1`. A phone on the LAN cannot reach them; see section 4.3 for that case.
`make logs` follows the logs, `make down` stops everything.

### 2.2 Without Docker (SQLite, verified)

Use three terminals, from the repo root.

```bash
# Terminal 1: verifier (stub mode)
cd backend/verifier && uv sync --frozen && uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8001 --no-access-log

# Terminal 2: API with a disposable SQLite database
cd backend/api && uv sync --frozen
export DATABASE_URL=sqlite:///./aldia.db PHOTO_DIR=/tmp/aldia-api-photos VERIFIER_URL=http://127.0.0.1:8001
export STAFF_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"   # see 2.3
uv run alembic upgrade head
uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --no-access-log

# Terminal 3: portal dev server (proxies /api to localhost:8000)
cd portal && npm ci && npm run dev          # http://localhost:5173
```

`CORS_ORIGINS` defaults to `http://localhost:5173`, which matches the dev server. For the container portal on port 8080
add `export CORS_ORIGINS=http://localhost:5173,http://localhost:8080` before starting the API.
Check: `curl -s localhost:8000/api/health` and `curl -s localhost:8001/health` answer `ok`.

### 2.3 STAFF_TOKEN

The staff endpoints answer `503` until `STAFF_TOKEN` (at least 32 characters) is set. Generate a random one locally:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(32))'     # 43 characters
```

- Docker: put it in your local `.env` as `STAFF_TOKEN=...`, then `make up` again (the file is git-ignored; never commit it).
- Without Docker: `export STAFF_TOKEN=...` in the shell that starts the API (as in 2.2).
- Optional `SUPERVISOR_TOKEN`, generated the same way and different from the first, enables supervisor-only actions
  (override verifier rejections, reopen resolved or closed cases, hide and restore).
- In the portal: open **Modo personal**, paste the token in **Token de personal**, choose **Operador** (or
  **Supervisor** with the supervisor token), press **Activar**. The token stays in memory only and disappears on reload.
- Never paste a token into chat, tickets or screenshots.

### 2.4 Demo data (seed)

```bash
make seed           # 44 synthetic reports, all 6 categories and all 11 states, spread over 60 days
make seed-reset     # remove the "[demo]" reports and create them again with fresh dates
```

`make seed` uses `DATABASE_URL` and `PHOTO_DIR` from your environment (defaults: `sqlite:///./aldia.db` and
`/tmp/aldia-api-photos` inside `backend/api`) and runs the migrations first. Use the same values as the running API.
The script refuses to run when `ALDIA_ENV`, `APP_ENV` or `ENVIRONMENT` is `production`. Seeded rows have a note starting
with `[demo]`, so re-running does not duplicate them. Expected output: `Created 44, already present 0.` then a summary
(rerun: `Created 0, already present 44.`).

Important: the list, stats and clusters default to the **last 30 days**. About half of the seeded reports (roughly 21 of 44) are older;
add `include_old=true` in API calls (the portal's date filter must go back far enough) to see all 44. Hidden (`oculto`)
reports are visible only in staff mode, so the public list shows 42 of the 44, and the portal in staff mode more.

Docker stack (not executed): the image does not contain `scripts/`, so copy it in and run it inside the container:

```bash
docker compose cp backend/api/scripts api:/tmp/scripts
docker compose exec -w /service api python /tmp/scripts/seed_demo.py
```

## 3. API with curl (verified)

Set once (the token from 2.3; use the same shell session):

```bash
API=http://localhost:8000/api
export STAFF_TOKEN=...            # the token you started the API with
```

**Create a report with an idempotency key.** `captured_at` must be within the last 10 minutes (verifier default).

```bash
python3 -c 'from PIL import Image; Image.new("RGB",(800,600),"gray").save("/tmp/aldia-test.jpg")'   # any 640x480+ JPEG works
KEY=$(python3 -c 'import uuid; print(uuid.uuid4())')
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
curl -s -w '\nHTTP %{http_code}\n' -X POST $API/reports -H "Idempotency-Key: $KEY" \
  -F photo=@/tmp/aldia-test.jpg -F category=pothole -F latitude=14.6349 -F longitude=-90.5069 \
  -F captured_at=$NOW -F note="prueba"
```

Expected: `HTTP 201`, `"status":"verified"`, `"state":"nuevo"`, verification `"mode":"stub"`. Repeat the exact same command with
the same `$KEY`: `HTTP 200` and the same `id` (no second report). A new key with the same photo and place within
50 m gives `201` with `"status":"rejected"` and a failed `duplicate` check.

**Read.**

```bash
ID=<id from the response>
curl -s "$API/reports/$ID" | python3 -m json.tool | head -40                    # includes events (oldest first)
curl -s -o /tmp/photo.jpg -w '%{http_code} %{content_type}\n' "$API/reports/$ID/photo"   # 200 image/jpeg
curl -s "$API/reports?state=nuevo&include_old=true&limit=5"
curl -s "$API/reports/nearby?lat=14.6349&lon=-90.5069&category=pothole&radius_m=300"   # items with distance_m and thumbnail_url
curl -s "$API/reports/clusters?bbox=-90.6,14.5,-90.4,14.7&zoom=12"                      # clusters with count, ids, total
curl -s "$API/stats?include_old=true"                                                   # recibidos, tasa_resolucion, weekly ...
curl -s "$API/open311/v2/requests.json" | head -c 400
```

**Staff transition.** Without the header: `401`. With a wrong token: `401`. With the API started without
`STAFF_TOKEN`: `503`. Illegal transition: `409`.

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST $API/reports/$ID/transition -H 'Content-Type: application/json' \
  -d '{"to":"en_revision"}'                                                        # 401
curl -s -X POST $API/reports/$ID/transition -H "X-Staff-Token: $STAFF_TOKEN" -H 'Content-Type: application/json' \
  -d '{"to":"en_revision","public_note":"Lo estamos revisando"}' | python3 -m json.tool | grep -E '"state"|public_note'
curl -s -w '\nHTTP %{http_code}\n' -X POST $API/reports/$ID/transition -H "X-Staff-Token: $STAFF_TOKEN" \
  -H 'Content-Type: application/json' -d '{"to":"resuelto"}'                       # 409: skips programado/en_proceso without a note
curl -s -X POST $API/reports/$ID/assign -H "X-Staff-Token: $STAFF_TOKEN" -H 'Content-Type: application/json' \
  -d '{"assignee":"Cuadrilla Norte"}' | grep -o '"assignee":"[^"]*"'
curl -s -H "X-Staff-Token: $STAFF_TOKEN" "$API/queue?tab=review" | head -c 300      # unassigned "nuevo" cases, oldest first
```

Legal transitions are in [api-contract.md](api-contract.md) (state machine). Typical path:
`en_revision` -> `programado` -> `en_proceso` -> `resuelto` (each step one call; skipping a step needs a note).

**CSV.**

```bash
curl -s -D - -o /tmp/aldia.csv "$API/reports.csv?delimiter=semicolon&include_old=true" | head -5
head -3 /tmp/aldia.csv       # UTF-8 BOM, then id;created_at;verified_at;category;state;...
```

Expected: `200`, `content-disposition: attachment; filename=aldia-reports.csv`, 14 columns, at most 5000 rows.

## 4. Manual QA scripts

Seed the demo data first (2.4) so there is something to look at. Report each failure with the step number.

### 4.1 Portal (not executed in a browser)

Open http://localhost:5173 (or :8080 with Docker). Use a recent Chrome or Firefox and the browser's device toolbar for 4.1.8.

1. **Map.** Pins and clusters appear around Guatemala City. Zoom in: clusters split into single pins (single reports from
   zoom 17). Click a pin: popup with category, date (Guatemala time) and photo; **Ver reporte completo** opens the
   detail page with the timeline. The URL changes and Back returns to the map.
2. **Filters.** Change **Categoría**, **Estado municipal** and the date range: the list **Reportes en esta zona** and the
   pins update together; **No hay reportes en esta zona con estos filtros.** appears when nothing matches. Date range
   wider than 30 days shows the older demo reports.
3. **Public mode.** Without a token the page says **Vista pública de solo lectura**; no action buttons.
4. **Staff mode.** Open **Modo personal**, paste the token (2.3), **Activar**. A token shorter than 32 characters shows
   **El token debe tener al menos 32 caracteres.**; a wrong token shows **Token no válido o permisos insuficientes**
   when you act. Reload: the token is gone.
5. **Triage.** In staff mode open **Bandeja de revisión**: tabs for new unassigned cases and for verifier rejections, oldest
   first with age. Assign a case to a crew; it leaves the review tab.
6. **State transition.** Open a `nuevo` report, move it to `en_revision`, then `programado`, `en_proceso`, `resuelto`,
   with a public message. Each step adds a timeline event. Try an illegal move (for example `nuevo` to `resuelto`): the
   portal shows an error and the state does not change. Closing states (`no_procede`, `fuera_de_competencia`) require
   a reason.
7. **Dashboard.** **Panel de reportes**: totals, received, open, resolved, resolution rate, median hours, SLA, ages and
   weekly chart change with filters. After step 6, resolved count rises by one (refresh if needed). Compare one number
   with `curl "$API/stats?include_old=true"`.
8. **CSV.** **Descargar CSV** with delimiter **Punto y coma** and again with **Coma**: file opens in a spreadsheet with
   accents intact and columns separated correctly; row count matches the filtered total.
9. **Keyboard only.** Put the mouse aside and use Tab, Shift+Tab, Enter, Space, Esc and the arrow keys. First Tab shows
   **Ir a los reportes** (skip link). Map moves with the arrows, `+` and `-` zoom. Every control shows a visible focus
   ring; popups close with Esc; the order of focus follows the visual order.
10. **Mobile width.** Resize to 360 px wide (and rotate to 640 px): no horizontal scroll, filters collapse and stay
    reachable, the map and the list are both usable, tap targets are at least about 44 px.
11. **Map tiles offline.** Disconnect the network after loading: the page shows the tile error text; reports still list.

### 4.2 App on an Android emulator (not executed)

1. Install Android Studio and one system image as in [dev-setup.md](dev-setup.md). Device Manager -> create a phone ->
   start it. In the emulator's **Extended controls -> Camera** set the back camera to **VirtualScene** (a synthetic room)
   or **Webcam0**; **Location** lets you set a point in Guatemala City (14.6349, -90.5069).
2. Start the stack (section 2) and seed (2.4). The API must be reachable from the emulator: it listens on
   `127.0.0.1:8000` of your computer, which the emulator sees as `10.0.2.2:8000`.
3. Run: `make app-run` (default `API_BASE_URL=http://10.0.2.2:8000/api`) or
   `cd app && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api`.
4. Onboarding: three pages (**Reporta lo que ves en tu calle**, **La foto se toma en el momento**, **Tu privacidad**);
   **Omitir** and **Empezar** work.
5. Map and list: demo reports appear as clusters or pins; **Lista** shows the same reports without the map; filters by
   **Estado** and **Categoría** work.
6. New report (**Reportar**), steps: **Ubicación** (permission prompt: allow while using the app; move the point by tapping the
   map), **Categoría**, **Foto** (**Tomar foto**; camera permission prompt), **¿Ya está reportado?** (nearby reports; choose
   **Es un problema distinto** or **Seguir este reporte**), **Revisar y enviar** -> **Enviar reporte**.
7. Result screen **Reporte verificado**. The verification is a stub (**Verificación de prueba: aún no se clasifica la foto.**).
8. **Permissions.** Deny location: **Permiso de ubicación denegado. Puedes elegir el punto en el mapa.** and manual
   coordinates still work. Deny camera forever: **No se pudo abrir la cámara...** and **Abrir ajustes**.
9. **Offline outbox.** Turn on airplane mode in the emulator (swipe down -> Airplane mode). Create and send a report: it
   shows **Esperando red** and appears under **Por enviar** (**Se enviará solo cuando vuelva la conexión.**). Turn airplane
   mode off: within a short time it is sent automatically (or press **Reenviar ahora**) and moves to **Mis reportes**.
   Check on the server that there is exactly one new report (retries use an `Idempotency-Key`). A photo older than 10
   minutes at send time is rejected with **La foto es demasiado antigua.**: the original capture time is sent, so this is
   expected after a long outage.
10. **Draft resume.** Start a report, take a photo, then leave with the system back button: the home shows **Tienes un
    reporte sin terminar.** and **Continuar borrador**. Resume: location, category, photo and note are kept. **Eliminar
    borrador** asks for confirmation.
11. **Timeline.** After staff changes a state in the portal (4.1.6), open the report in **Mis reportes**: **Historial**
    shows the new events and **Mensaje del municipio** shows the public note.

### 4.3 App on a real Android phone (not executed)

1. Enable Developer options and USB debugging; connect by USB; accept the prompt; `flutter devices` lists the phone.
2. The API must listen on the LAN: start uvicorn with `--host 0.0.0.0` (without Docker) or change the published port in
   a local override. Find your IP (`ip -4 addr` on Linux, `ipconfig getifaddr en0` on macOS). Phone and computer must be on
   the same Wi-Fi, and the computer's firewall must allow port 8000. The app needs no CORS entry (native apps send no
   `Origin`); a portal opened from another machine does need its origin in `CORS_ORIGINS`.
3. Run: `cd app && flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:8000/api`. Debug builds allow cleartext HTTP; a
   **release** build does not (see troubleshooting): use HTTPS for release.
4. Repeat 4.2 steps 4 to 11 with the real camera and GPS. Extra checks outdoors: **Precisión GPS** under 50 m
   (otherwise **La precisión supera 50 m. Reintenta el GPS...**), photo taken from the sidewalk, no people in frame.
5. Do not expose `0.0.0.0` on a public network; use a private Wi-Fi and stop the API afterwards.

### 4.4 App on the iOS simulator and a real iPhone (macOS only, not executed)

1. Xcode setup as in [dev-setup.md](dev-setup.md): `cd app && flutter pub get && cd ios && pod install`, open
   `app/ios/Runner.xcworkspace`, set the team under **Signing & Capabilities** (a free Apple ID works for the simulator
   and your own phone).
2. **Simulator:** `flutter run -d <simulator id> --dart-define=API_BASE_URL=http://localhost:8000/api`. The simulator has
   no camera and the app currently uses the live camera only (`ImageSource.camera` in `app/lib/services/photo_service.dart`;
   no gallery fallback exists), so the **Foto** step fails with **No se pudo abrir la cámara...**. In the simulator you
   can test onboarding, map, list, filters, detail and timeline of seeded reports, location (Features -> Location ->
   Custom Location 14.6349, -90.5069) and drafts up to the photo step. The full report flow needs a real iPhone.
3. **Real iPhone:** connect, trust the computer, enable Developer Mode (Settings -> Privacy & Security), choose the
   phone as the run destination, and run with `--dart-define=API_BASE_URL=http://<LAN-IP>:8000/api`. First launch:
   Settings -> General -> VPN & Device Management -> trust your developer profile.
4. Permissions: camera and location prompts use the texts in `ios/Runner/Info.plist`. iOS also asks once for **Local
   Network** access when the app first talks to a LAN IP: allow it, otherwise requests time out
   (**No se pudo enviar el reporte. Revisa tu conexión.**). Fix: Settings -> Aldia -> Local Network. Note: the
   Info.plist currently has no `NSLocalNetworkUsageDescription`; if the prompt does not appear or requests are blocked,
   add it (needs a team decision, `app/` is not part of this guide).
5. HTTP to a LAN IP needs an App Transport Security exception in debug; if requests fail with an ATS error, use an HTTPS
   tunnel for the test (not executed, check on first run).
6. Repeat 4.2 steps 4 to 11 (airplane mode is in Control Center).

### 4.5 Verifier stub behavior (verified)

The stub never classifies: the `category` check always passes with `stub: not classified`. Mechanical checks are real:

| Check | Fails when | Result in API |
|---|---|---|
| `image` | smaller than 640x480 or undecodable | `rejected` (`rechazado_verificador`); undecodable image gives `422` |
| `place` | outside the bounding boxes of Guatemala, Colombia, Mexico | `rejected` |
| `freshness` | `captured_at` older than 600 s or more than 60 s in the future | `rejected` ("La foto es demasiado antigua.") |
| `category` | never in stub mode | passes, detail `stub: not classified` |
| `duplicate` (added by the API) | same category, dHash distance <= 4, within 50 m | `rejected`, `HTTP 201` |

Try it: repeat the create command from section 3 with `captured_at=2026-01-01T00:00:00Z` (freshness fails), with
`latitude=40.4 longitude=-3.7` (place fails), and with a 320x240 JPEG (image fails). Stop the verifier and create a
report: the report stays `pending` / `pendiente_verificacion` with `"verification": null` (the app shows **Reporte
recibido, verificación pendiente**; there is no retry worker yet). A stub result is not a real verification and must be
presented as such to the government.

## 5. End-to-end scenario

Goal: one citizen report travels through the whole system. Needs the stack (2.2 or 2.1), seeded data (2.4) and a
`STAFF_TOKEN`.

1. **Citizen (app).** In the app, send a new `pothole` report from Guatemala City with a fresh photo. Note the
   **Referencia** id on the result screen. Expected: **Reporte verificado**.
   Without a phone: run the curl create command from section 3 (same effect, `captured_at` fresh).
2. **Verifier.** `curl -s $API/reports/$ID` shows `"status":"verified"`, `"state":"nuevo"` and four `ok` checks plus
   `duplicate`, `"mode":"stub"`. Events: `pendiente_verificacion` then `nuevo`.
3. **Portal.** Reload the portal: the new pin is on the map and in **Bandeja de revisión** (staff mode, `nuevo`, no assignee).
4. **Staff.** Assign it to a crew, move it `en_revision` -> `programado` -> `en_proceso` -> `resuelto`, with the public
   message **Reparacion terminada, gracias por avisar.** on the last step. The dashboard resolved count rises by one and
   the CSV contains the row with state `resuelto` and a `resolved_at` value.
5. **Citizen (app).** Pull to refresh in **Mis reportes**: the report shows the resolved state; **Historial** lists all steps
   in order and **Mensaje del municipio** shows the public message. Internal notes never appear in the app.
6. **Negative path.** Repeat step 1 with the same photo at the same place within a minute: the second report is
   `rejected` with **Reporte similar** (duplicate check). The app's **¿Ya está reportado?** step should have offered the
   first report before sending.

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Portal shows an error and the browser console says CORS | origin not in `CORS_ORIGINS` (default only `http://localhost:5173`) | export `CORS_ORIGINS=http://localhost:5173,http://localhost:8080` and restart the API. Check: a request with `Origin: http://localhost:5173` returns `access-control-allow-origin`; other origins get none |
| Staff action returns `503` `staff_unavailable` ("Acceso de personal no configurado.") | API started without `STAFF_TOKEN` | generate a token (2.3), set it, restart the API (Docker: edit local `.env`, `make up`) |
| Staff action returns `401` | missing, wrong or too short token; wrong role token | paste the same token the API started with; supervisor-only actions need `SUPERVISOR_TOKEN` |
| Staff action returns `409` | illegal transition or missing note | check the transition table in the API contract; add a `public_note` or `internal_note` |
| `make up` fails with `set POSTGRES_PASSWORD in .env` | `.env` missing or empty | `cp .env.example .env` and set it |
| App cannot reach the API on a real release build: "cleartext not permitted" | Android release builds block plain HTTP (only the debug manifest allows it) | use an HTTPS URL for release; for tests use a debug build |
| App on Android emulator times out | `localhost` used instead of `10.0.2.2`, or API bound to another interface | `--dart-define=API_BASE_URL=http://10.0.2.2:8000/api`; API on `127.0.0.1:8000` is enough |
| App on phone times out | phone not on the same Wi-Fi, API bound to `127.0.0.1`, firewall, iOS Local Network permission denied | `--host 0.0.0.0`, allow port 8000, use the LAN IP, allow Local Network on iOS |
| Report rejected, "La foto es demasiado antigua." (`freshness`) | photo older than 600 s, or phone clock wrong | take a new photo; check the device time zone and clock; a long offline period causes it too |
| Report rejected, place check | point outside Guatemala, Colombia or Mexico boxes (emulator default location is California) | set the emulator location to Guatemala City |
| "La precisión supera 50 m" | weak GPS indoors or on an emulator | go outside, retry GPS, or adjust the point on the map |
| Report is `pending`, no verification | verifier unreachable or timed out (3 s connect, 10 s total, no retries) | start the verifier, check `VERIFIER_URL`; create a new report (no retry worker) |
| Portal or list is missing demo reports | default window is the last 30 days; hidden reports are staff only | widen the date range, use `include_old=true`, enable staff mode |
| Seed prints "Database error" | schema not migrated, or different `DATABASE_URL` than the API | `uv run alembic upgrade head`; use the same `DATABASE_URL` and `PHOTO_DIR` |
| Seed prints "Refusing to seed demo data" | `ALDIA_ENV`, `APP_ENV` or `ENVIRONMENT` is `production` | intended; never seed production |
| Photos missing in the portal after seeding | `PHOTO_DIR` differs between seed and API | use the same directory (the seed also restores missing photos on a rerun) |
| iOS simulator: no camera | simulator limitation | use a real iPhone for the photo step |
| `flutter test` fails in an unrelated screen | someone is editing `app/` | pull, rerun, ask the owner |

## 7. Checklist for a demo to a government

Prepare the day before; run the whole list again one hour before.

**Data and environment**

- [ ] Fresh database; `make seed-reset` run on the demo environment (never on production data). Demo reports say
      `[demo]` and use synthetic photos; no real people, plates or private places.
- [ ] Stack on a stable machine (not a laptop on guest Wi-Fi); `curl $API/health` is `ok`; verifier `ok`.
- [ ] `STAFF_TOKEN` generated for the demo, stored in a password manager, not on slides or screens; different from any
      other environment. Supervisor token ready if overrides will be shown.
- [ ] Portal opens on the map with data (not empty), date filter covers the whole demo period, dashboard shows numbers.
- [ ] Browser zoom 100 %, notifications off, bookmarks and tabs clean, no `.env` or token visible.

**Devices**

- [ ] Phone charged, camera and location permissions granted, on the same network as the API, release or debug build
      installed, onboarding already seen or ready to show.
- [ ] Emulator or screen mirror as backup; a short screen recording of the happy path as a last resort.
- [ ] Mobile data or hotspot as a second network.

**Story (about 10 minutes)**

- [ ] Citizen reports with a live photo -> verified -> appears in the portal (section 5).
- [ ] Staff triages and resolves; citizen sees the update and the official message.
- [ ] Dashboard: received, resolved, resolution rate, SLA, age buckets; CSV export; Open311 view.
- [ ] Show a rejected photo (old or duplicate) to explain verification and duplicates.

**Honest limits to state**

- [ ] The verifier runs in `stub` mode: it checks image, place, freshness and duplicates, but does **not** classify the
      category yet. Say so; never call it AI verification.
- [ ] Staff login is a shared token (stopgap) to be replaced by phone-code login; the PoC is not secured for production.
- [ ] Photos and points are public; payouts, rewards and taxes are not part of the MVP (open topics, decided with the
      first government).
- [ ] Map tiles come from public OpenStreetMap servers (light use); a tile provider is needed for real traffic.
- [ ] Only the demo or consented photos are used; all demo data is synthetic.

**After the demo**

- [ ] Stop the stack (`make down`), remove the demo data if the machine is shared, rotate the demo token.
- [ ] Note questions and feature requests in `docs/` or the team workspace, not in this public repo if they include strategy.
