# API contract (v0, MVP boilerplate)

Single source of truth for `app/`, `portal/` and `backend/`. If code and this file disagree, fix them in the same
change. JSON uses `snake_case`. Times are ISO 8601 in UTC (`2026-11-19T18:30:00Z`).

## Categories

Ids are stable. The final MVP list depends on what the verifier can recognize in photos (Lorenz); change it in one place
per service (`backend/api/app/categories.py`, `app/lib/core/categories.dart`, `portal/src/categories.js`).

| id | Spanish label |
|---|---|
| `accessibility` | Accesibilidad (rampas, bordillos) |
| `sidewalk` | Acera en mal estado |
| `pothole` | Bache |
| `graffiti` | Grafiti |
| `open_drain` | Alcantarilla abierta |
| `street_light` | Luminaria dañada |

## Services and ports

| Service | Port | Notes |
|---|---|---|
| `backend/api` | 8000 | public API below, prefix `/api` |
| `backend/verifier` | 8001 | internal, never published to the internet |
| `portal` (dev server) | 5173 | proxies `/api` to the API |
| `portal` (container) | 8080 | nginx, proxies `/api` to `api:8000` |
| Postgres | 5432 | only inside the compose network by default |

## Public API (`backend/api`)

Errors: `{"error": {"code": "string", "message": "string"}}` with the matching HTTP status.

### Report object

```json
{
  "id": "uuid",
  "category": "pothole",
  "latitude": 14.6349,
  "longitude": -90.5069,
  "captured_at": "2026-11-19T18:30:00Z",
  "created_at": "2026-11-19T18:30:05Z",
  "status": "verified",
  "note": null,
  "photo_url": "/api/reports/<id>/photo",
  "verification": {
    "passed": true,
    "mode": "stub",
    "checks": [{"name": "freshness", "passed": true, "detail": "age 5 s"}]
  }
}
```

`status` is `pending` (verifier unreachable, `verification` is `null`), `verified` or `rejected`.

`resolution` (added in v0.1, from SeeClickFix's open / acknowledged / closed) is the government's handling state:
`open` (default), `acknowledged` or `fixed`. In v0 nobody can change it through the API (no auth yet); it is stored so
the portal and the app can already show it. Add `"resolution": "open"` to the report object above.

### Endpoints

| Method and path | Purpose |
|---|---|
| `GET /api/health` | Dependency readiness: `{"status":"ok","dependencies":{"database":"ok","verifier":"ok","photos":"ok"}}`; 503 with `status: degraded` and `unavailable` for failed dependencies. |
| `GET /api/categories` | `[{"id": "pothole", "label": "Bache"}]` |
| `POST /api/reports` | `multipart/form-data`: `photo` (JPEG or PNG, max 8 MB), `category`, `latitude`, `longitude`, `captured_at`, optional `note` (max 280). Returns `201` + report. The API calls the verifier, adds the `duplicate` check and stores the result. |
| `GET /api/reports` | Query: `bbox=min_lon,min_lat,max_lon,max_lat`, `category`, `status`, `limit` (1-500, default 100), `offset`. Returns `{"items": [report], "total": 0}` newest first. |
| `GET /api/reports/{id}` | One report, `404` if unknown. |
| `GET /api/reports/{id}/photo` | Stored photo (EXIF and GPS removed), `image/jpeg`. |
| `GET /api/stats` | v0.1, for the portal dashboard: `{"total": 0, "by_category": {"pothole": 0}, "by_status": {"verified": 0}, "by_resolution": {"open": 0}}`. Same optional filters as the list (`bbox`, `category`, `status`, `resolution`). |
| `GET /api/reports.csv` | v0.1, CSV export with the same filters: `id,category,latitude,longitude,captured_at,created_at,status,resolution,photo_url`. |
| `GET /api/open311/v2/requests.json` | v0.1, read-only Open311 GeoReport v2 view of verified reports: `service_request_id`, `status` (`open` or `closed`, closed when `resolution` is `fixed`), `service_code` (category id), `service_name` (label), `description` (note), `lat`, `long`, `requested_datetime`, `updated_datetime`, `media_url`. |
| `GET /api/open311/v2/services.json` | Six category services: `service_code`, Spanish `service_name` and `description`, `metadata: false`, `type: realtime`, `keywords`, `group`. |

The list also accepts `resolution=open|acknowledged|fixed`.

Rules: the API strips EXIF before storing; it never logs coordinates with a worker identity; ids are validated as UUIDs
before any path use. There is no authentication in v0: the PoC shows synthetic or consented photos only. Deciding
auth (citizen device, government portal login) is an open decision (`documentation/decisions/`).

## Verifier API (`backend/verifier`)

`GET /health` returns `{"status": "ok", "mode": "heuristic"}` without a model.
`VERIFIER_MODE=model` fails startup with an explicit `NotImplementedError` until Lorenz integrates a model.
The legacy configuration value `stub` is accepted as an alias for `heuristic`; responses never use `mode: "stub"`.

`POST /verify` (`multipart/form-data`: `photo`, `category`, `latitude`, `longitude`, `captured_at`) returns
all existing v0.2 fields, adding a machine-readable `code` to every named check:

```json
{
  "passed": true,
  "mode": "heuristic",
  "phash": "f0e4c2a1b3d5978f",
  "checks": [
    {"name": "image", "passed": true, "detail": "1280x960; mínimo 640x480", "code": "image_ok"},
    {"name": "place", "passed": true, "detail": "inside GT", "code": "place_ok"},
    {"name": "freshness", "passed": true, "detail": "antigüedad 5 s", "code": "freshness_ok"},
    {"name": "sharpness", "passed": true, "detail": "varianza laplaciana 240.00; mínimo 80.00", "code": "sharpness_ok"},
    {"name": "exposure", "passed": true, "detail": "luminancia media 128.00; píxeles recortados 0.0000", "code": "exposure_ok"},
    {"name": "exif_time", "passed": true, "detail": "sin EXIF", "code": "exif_missing"},
    {"name": "exif_gps", "passed": true, "detail": "sin EXIF", "code": "exif_missing"},
    {"name": "screen_photo", "passed": true, "detail": "sin patrón periódico significativo", "code": "screen_clear"},
    {"name": "category", "passed": true, "detail": "no clasificado (sin modelo)", "code": "category_stub"}
  ]
}
```

`phash` remains a 64-bit difference hash as 16 hex characters. The API compares it with stored reports of the
same category (Hamming distance <= 4 within 50 m) and appends its own `duplicate` check.
Overall `passed` is the conjunction of the hard checks; `screen_photo` always passes and cannot reject a report.

| Check | Rule and codes |
|---|---|
| `image` | JPEG/PNG decodes safely, oriented size >= 640x480 (`image_ok`, `image_too_small`). Undecodable/unsupported content returns 422. |
| `place` | Inside the broad bounding boxes of Guatemala, Colombia or Mexico (`place_ok`, `place_outside`). These are not country polygons or proof of location. |
| `freshness` | Submitted capture time within `MAX_AGE_SECONDS` of server time, with at most 60 s future tolerance (`freshness_ok`, `freshness_outside`). |
| `sharpness` | Variance of signed four-neighbor Laplacian on grayscale, aspect-preserving downscale to at most 320x320, excluding borders; >= `SHARPNESS_MIN` (`sharpness_ok`, `blurry`). Detail includes measured variance. |
| `exposure` | Mean grayscale luminance in the inclusive configured range and fraction of pixels <= 5 or >= 250 at most `EXPOSURE_MAX_CLIPPED_RATIO`, on the same downscale (`exposure_ok`, `underexposed`, `overexposed`, `exposure_clipped`). Detail includes both measurements. |
| `exif_time` | EXIF DateTimeOriginal age must be in [-60, `MAX_AGE_SECONDS`] and within ±120 s of submitted `captured_at` (`exif_time_ok`, `exif_time_outside`, `exif_time_mismatch`, `exif_time_invalid`). OffsetTimeOriginal is honored; absent offset is explicitly interpreted as UTC because camera EXIF often has no timezone. Missing DateTimeOriginal passes as `exif_missing`, detail exactly `sin EXIF`; malformed present metadata fails. |
| `exif_gps` | Present EXIF GPS must parse as valid DMS coordinates and be <= 150 m from the submitted point by haversine (`exif_gps_ok`, `exif_gps_mismatch`, `exif_gps_invalid`); detail includes distance, never coordinates. Missing GPS passes as `exif_missing`, detail exactly `sin EXIF`. |
| `screen_photo` | **Soft** periodic-pattern hint using FFT-free autocorrelation of second differences of row/column mean luminance on an at-most-128x128 downscale. A strong local correlation peak produces `possible_screen` with an explanation, otherwise `screen_clear`; both have `passed: true`. The API may route the hint to manual review later; no routing is added here. |
| `category` | Placeholder accepts supported category IDs with `category_stub`, detail exactly `no clasificado (sin modelo)`. Real category recognition requires Lorenz's model. |

Heuristic thresholds (process environment, validated in `backend/verifier/app/config.py`):

| Variable | Default | Meaning |
|---|---|---|
| `VERIFIER_MODE` | `heuristic` | `heuristic`, legacy alias `stub`, or explicit unimplemented `model`. |
| `MAX_AGE_SECONDS` | `600` | Maximum age for submitted and EXIF times, seconds. |
| `SHARPNESS_MIN` | `80` | Minimum Laplacian variance after downscaling. |
| `EXPOSURE_MIN_MEAN` | `12` | Minimum mean luminance, 0–255. |
| `EXPOSURE_MAX_MEAN` | `243` | Maximum mean luminance, 0–255. |
| `EXPOSURE_MAX_CLIPPED_RATIO` | `0.95` | Maximum combined near-black/near-white pixel fraction, 0–1. |
| `SCREEN_MIN_CORRELATION` | `0.85` | Minimum periodic local correlation peak (lags 2–16). |

These deterministic checks measure image usability and metadata consistency, **not** authenticity, trusted capture,
category recognition or proof of a street problem. EXIF can be absent or forged; texture/noise can pass sharpness,
repeating real-world patterns can trigger the soft screen hint, and some screen photographs will evade it.
Defaults are calibrated only against reproducible synthetic Pillow fixtures, not validated on a real-photo dataset.

## Configuration (environment variables)

| Service | Variable | Default |
|---|---|---|
| api | `DATABASE_URL` | `postgresql+psycopg://aldia:aldia@db:5432/aldia` |
| api | `PHOTO_DIR` | `/data/photos` |
| api | `VERIFIER_URL` | `http://verifier:8001` |
| api | `MAX_UPLOAD_BYTES` | `8388608` |
| api | `CORS_ORIGINS` | `http://localhost:5173` |
| verifier | `VERIFIER_MODE` | `heuristic` |
| verifier | `MAX_AGE_SECONDS` | `600` |
| portal | `VITE_API_BASE_URL` | `/api` |
| app | `--dart-define=API_BASE_URL=...` | `http://10.0.2.2:8000/api` (Android emulator) |

## v0.2 additions: case states, staff actions, triage, clustering (inspired by the FixMyStreet study)

Written from our own behavior spec (clean-room, see `documentation/research/reference-fixmystreet-seeclickfix.md`).
Everything below is **additive**: v0.1 fields and endpoints keep working.

### Case state machine

`state` is the municipality's handling state. `status` (pending/verified/rejected) stays the verifier verdict.

| `state` | group (`state_group`) | meaning |
|---|---|---|
| `pendiente_verificacion` | `pending` | created, verifier not answered yet (system) |
| `rechazado_verificador` | `closed` | verifier rejected the photo (system); staff may override |
| `nuevo` | `open` | verified, not yet looked at |
| `en_revision` | `open` | being reviewed, usually assigned |
| `programado` | `in_work` | work scheduled |
| `en_proceso` | `in_work` | work in progress |
| `resuelto` | `resolved` | fixed (sets `resolved_at`) |
| `no_procede` | `closed` | rejected by staff, reason required |
| `fuera_de_competencia` | `closed` | not the municipality's job, reason required |
| `duplicado` | `closed` | duplicate of `duplicate_of`, reason optional |
| `oculto` | `hidden` | moderated, hidden from the public list; restores to the previous state |

Creation sets `pendiente_verificacion`; verifier pass moves to `nuevo`, verifier fail to `rechazado_verificador`;
unreachable verifier keeps `pendiente_verificacion` (`status` stays `pending`). Legal transitions (everything else is `409`):

- `rechazado_verificador` → `nuevo` (supervisor override, `internal_note` required)
- `nuevo` → `en_revision`
- `en_revision` → `programado`, `en_proceso`, `no_procede`, `fuera_de_competencia`, `duplicado`
- `programado` → `en_proceso`, `no_procede`
- `en_proceso` → `resuelto`
- `resuelto` → `en_revision` (reopen)
- `no_procede`, `fuera_de_competencia`, `duplicado` → `en_revision` (reason required)
- open states may move backwards to an earlier open state; any state → `oculto`; `oculto` → previous state.
- closing states (`no_procede`, `fuera_de_competencia`) and any forward skip need a non-empty `public_note` or `internal_note`.

`resolution` (v0.1) is now derived: `open` for pending/open groups, `acknowledged` for `in_work`, `fixed` for `resuelto`,
`closed` for the other closed states. `closed` is a new allowed value.

### Report object additions

`state`, `state_group`, `state_changed_at`, `verified_at` (null until the verifier answers), `resolved_at`, `closed_at`,
`assignee` (string or null), `duplicate_of` (uuid or null), `public_note` (last public message, or null).
`GET /api/reports/{id}` also returns `events`: `[{"at", "actor_role": "system|operator|supervisor", "from_state", "to_state", "public_note"}]`
(oldest first); internal notes appear only with a staff token. Reports in state `oculto` are excluded from the public
list and stats and return `404` on the detail endpoint without a staff token.

### Staff authentication (v0.2 stopgap)

Write endpoints and internal notes need the header `X-Staff-Token` equal to env `STAFF_TOKEN` (min 32 chars,
constant-time compare, no default: if unset, staff endpoints answer `503`). One shared token = one role `operator`; a
second token `SUPERVISOR_TOKEN` (optional) gives role `supervisor` for overrides, reopen from closed states and
`oculto`. This is replaced by phone-code login before any real deployment; the portal keeps the token in memory only.

### New endpoints

| Method and path | Purpose |
|---|---|
| `POST /api/reports/{id}/transition` | staff. Body `{"to": state, "public_note"?: str(<=280), "internal_note"?: str(<=500), "duplicate_of"?: uuid}`. Validates the table above, stores an event, returns the report. |
| `POST /api/reports/{id}/assign` | staff. Body `{"assignee": str(<=60) or null}`; stores an event-free assignment record (`assigned_at`). |
| `GET /api/reports/{id}/nearby` | open reports of the same category within 100 m created in the last 30 days (excludes itself), nearest first, max 10, with thumbnail url. For duplicate suggestions. |
| `GET /api/reports/clusters` | `bbox` (required), `zoom` (0-20). Grid-clustered pins: `{"clusters": [{"lat","lon","count","ids"?: [first 5 ids]}], "total"}`. At zoom >= 15 returns single reports (see v0.5). Max 500 items. Light payload (no photos). |
| `GET /api/queue` | staff-friendly triage list: `?tab=review|rejected`; `review` = state `nuevo` and no assignee, oldest `verified_at` first, each with `age_hours`; `rejected` = state `rechazado_verificador`. Same pagination as the list. |

### List, stats and export changes

- `GET /api/reports` new filters: `state`, `state_group`, `assignee`, `created_from`, `created_to` (ISO dates),
  `sort` (`newest` default, `oldest`, `updated`, `age_in_state`), `limit` (max 100 when paginating), `offset`. Response adds
  `"limit"` and `"offset"` echo fields. Default window without `created_from`: last 90 days unless `include_old=true`.
- `GET /api/stats` adds (same filters, municipality day boundaries `America/Guatemala`):
  `recibidos`, `rechazados_verificador`, `abiertos`, `resueltos`, `cerrados_sin_solucion`, `tasa_resolucion` (a ratio from 0 to 1, not a percentage: resueltos created in
  the period / (recibidos - duplicados - fuera_de_competencia), null if the denominator is 0), `resolucion_horas`
  `{"median","p90","mean","n"}` (resolved only, `resolved_at - verified_at`), `primera_respuesta_horas` `{"median","p90","n"}`,
  `antiguedad_abiertos` `{"0-2","3-7","8-30",">30"}` (days since `verified_at`), `sla_cumplido` (share of resolved within category SLA,
  null when none) and `vencidos` (open and older than the category SLA), `by_state`, `by_state_group`, `weekly`
  `[{"week": "2026-W47", "recibidos": 0, "resueltos": 0}]`. Category SLA hours live next to the categories
  (`backend/api/app/categories.py`): accessibility 720, sidewalk 720, pothole 240, graffiti 1440, open_drain 72, street_light 168.
- `GET /api/reports.csv` adds `delimiter=comma|semicolon` (default comma), writes a UTF-8 BOM, new columns
  `id,created_at,verified_at,category,state,state_changed_at,resolved_at,latitude,longitude,assignee,verifier_status,duplicates_count,days_open,link`
  (no personal data); still capped and formula-injection safe for text cells only. Hidden reports are excluded.
- Open311 view: `status` is `closed` for groups `resolved` and `closed`, else `open`.

### Categories

`GET /api/categories` adds `sla_hours` and `group` (`"movilidad"`, `"espacio_publico"`, `"servicios"`) per item.

### App support (v0.2)

- `POST /api/reports` accepts an `Idempotency-Key` header (a UUID generated by the app per report). A repeated key within 24 hours
  returns the original report with `200` and creates nothing, so retries after a timeout never duplicate a report.
- `GET /api/reports/nearby?lat=&lon=&category=&radius_m=150` (public, same rules as `/{id}/nearby`; `radius_m` 20-500, default 150):
  open verified reports of that category created in the last 30 days, nearest first, max 10, each with a thumbnail url. The app
  calls it before the details step to avoid duplicates. Declare it before the `/{id}` route.
- Each event in `events` also carries `public_note` so the citizen timeline can show official messages.

## v0.3 additions: category statistics

Additive extension of `GET /api/stats`; all v0.1/v0.2 fields and their formulas stay unchanged.
Inspired by Isabel Sagastume's dashboard statistics and accessible chart/table ideas, adapted to this contract.
Calculations live on the API, never on a paginated portal list.

### Category cohort and filters

The new fields use the same public visibility and filters as `GET /api/reports`: `bbox`, `category`, `status`,
`resolution`, `state`, `state_group`, `assignee`, `created_from`, `created_to`, `include_old`. The creation-date
window uses `America/Guatemala` day boundaries and defaults to the last 90 days. Pagination and `sort` do not
affect statistics. Hidden reports are always excluded.

Unlike the existing v0.2 aggregate resolution metrics (which select resolutions in the period), every new
category metric describes reports **created in the filtered period**, including their current handling state
and repair duration even if resolved after that period. An older report resolved during the period is excluded
from these new fields. This makes category totals agree with `by_category` and the filtered list.

### Response additions

`por_categoria` contains one row per stable category id (including zero-count rows), ordered by category id:

```json
{
  "category": "pothole",
  "total": 6,
  "resueltos": 3,
  "abiertos": 2,
  "cerrados": 1,
  "mediana_reparacion_horas": 10.0,
  "p90_reparacion_horas": 18.0,
  "n_resueltos": 3
}
```

- `total`: all reports in the category cohort.
- `resueltos`: current state `resuelto`.
- `abiertos`: groups `pending`, `open` and `in_work` (includes pending verification).
- `cerrados`: group `closed` (includes verifier rejections as well as staff closures).
  Thus `total = resueltos + abiertos + cerrados`. These category buckets are not the v0.2 top-level counters.
- Repair times: `(resolved_at - verified_at)` in hours, only for current state `resuelto` with both timestamps.
  Reopened reports do not contribute. `n_resueltos` is the count of valid duration samples, which can be lower
  than `resueltos` for incomplete legacy data. Median is the middle sorted sample, or the mean of the two middle
  samples. p90 uses linear interpolation at index `(n - 1) * 0.9`; no intermediate rounding.
  Both times are `null` when `n_resueltos = 0`; a real zero-hour duration remains `0`.
- `top_categorias`: up to five of the same row objects with `total > 0`, ordered by `total` descending,
  then category id ascending to break ties. Empty cohort: `[]`.
- `por_municipio_zona` is **omitted**: reports have no municipality/zone field. Coordinates and demo-note zone
  text are not a reliable zone classification; no zone is inferred.

The portal displays repair-time and stacked frequency SVG charts with textual labels, hover/focus tooltips,
and a keyboard-operable **Ver tabla** disclosure containing the same values (including sample counts and nulls).

## v0.4 additions: staff accounts and sessions

This section supersedes v0.2 shared staff authentication; v0.2 state rules and v0.3 statistics remain binding.
Roles are `operator`, `supervisor`, `admin`. Admin inherits supervisor case permissions; only admin manages users.

| Method and path | Request and response |
|---|---|
| `GET /api/auth/config` | Public: `{"enabled": true, "dev_tokens": false}`. The fallback flag is true only with both `ENV=dev` and `AUTH_DEV_TOKENS=true`. |
| `POST /api/auth/login` | JSON `{"username": "…", "password": "…"}`; 200 `{"user": {"username": "…", "role": "operator"}}`. Sets session and CSRF cookies. |
| `GET /api/auth/me` | 200 same user envelope for a valid session; otherwise 401. |
| `POST /api/auth/logout` | Session + CSRF; 204, revokes the session and expires both cookies. |
| `GET /api/admin/users` | Admin: `{"items": [{"id": "uuid", "username": "…", "role": "operator", "disabled": false}]}`. No password/hash/session data. |
| `POST /api/admin/users` | Admin + CSRF: `{"username": "…", "password": "…", "role": "operator"}`; 201 user object. Duplicate username: 409. |
| `PATCH /api/admin/users/{id}` | Admin + CSRF: any non-empty subset of `disabled` (boolean), `password` (reset), `role`; 200 user object, 404 if absent. Revokes all target sessions and clears lockout on password reset. |

Usernames are lowercase ASCII `[a-z0-9_][a-z0-9_.-]{2,63}`; passwords are 12–1024 characters and never trimmed.
Password hashing is Argon2id v19, memory 65536 KiB, time cost 3, parallelism 4, salt 16 bytes, hash 32 bytes.
Failed/unknown/disabled logins return a generic 401. Five failures lock an account for 15 minutes (423, including
the fifth attempt); successful authentication resets failures. Login requests are limited to 10 per 15 minutes per
normalized username + direct peer IP (429 + Retry-After). The in-memory limiter is per process; lockouts persist in SQL.

`aldia_session` contains a signed random opaque id, with a server-side SQL session expiring absolutely after 12 h.
Login rotates the presented session. Cookie flags: `HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=43200`;
only `ENV=dev` disables Secure. `aldia_csrf` has the same lifetime, Secure/SameSite/Path, but is readable by JavaScript.
Every session-authenticated state-changing staff request (including logout and user management) must send
`X-CSRF-Token` matching both the CSRF cookie and the server-side session value, using constant-time comparison;
missing/mismatching values return 403. Login validates any supplied Origin against the configured allowlist or
its own origin to prevent login CSRF. Passwords and session credentials never enter browser storage or URLs.
Auth responses use `Cache-Control: no-store`. Credentialed CORS permits explicit origins, PATCH and X-CSRF-Token.

Staff reads/writes accept the session cookie. `X-Staff-Token` is rejected with 401 by default; it is accepted only
when `ENV=dev` and `AUTH_DEV_TOKENS=true`, logging a warning without the credential. This explicit header fallback
does not require CSRF and never grants admin permissions. A supplied session takes precedence over the fallback.
The portal exposes a dev-token panel only when config reports `dev_tokens: true`.

Report events add `actor` (real username, or `system`; legacy events use `legacy:<role>` because their identity is
unknown) and retain `actor_role`, extended with `admin`. Dev fallback actors use `dev:<role>`.
Login successes/failures, logout and user creation/updates are stored in a separate audit table with actor,
actor_role, action, target and time; no passwords, cookie values or headers are audited.
The seed creates `operador` and `supervisor` accounts only with `ENV=dev`, printing a random password once per newly
created account. Production bootstrap uses `python -m app.cli create-admin`, with a password prompt or stdin,
never a password argument. See `decisions/staff-auth.md` for operational limits.

## Demo-readiness hardening

Public `POST /api/reports` and `POST /api/auth/login` share a per-peer-IP,
per-process sliding-window budget (default 60 requests/60 seconds; configurable
with `PUBLIC_POST_RATE_LIMIT` and `PUBLIC_POST_WINDOW_SECONDS`). Invalid requests
and idempotent retries count. Rejections return the uniform `rate_limited`
envelope, HTTP 429 and numeric `Retry-After`. The existing username/IP login
limiter and account lockouts remain in effect. Staff case writes require their
existing session/CSRF authorization and do not consume this public budget.

Report multipart bodies are capped at `MAX_UPLOAD_BYTES + 65536`; other
POST/PUT/PATCH bodies at `MAX_REQUEST_BYTES` (default 65536). Excess returns 413
with the existing `upload_too_large` envelope. CORS permits explicit origins only
from `CORS_ORIGINS`; wildcard, path and credential forms fail configuration.
All API responses include `X-Content-Type-Options: nosniff`,
`Referrer-Policy: no-referrer` and
`Permissions-Policy: camera=(), microphone=(), geolocation=()`.

Health is dependency readiness: SQL connectivity, verifier health and actual
private-photo-directory write. It returns 200 when all three are available,
otherwise 503 with a `status`/`dependencies` envelope (the deliberate exception
to the error envelope). It reveals no connection details or filesystem paths.
Verifier network-operation timeout is configurable by `VERIFIER_TIMEOUT_SECONDS`
(default 10 seconds); failed verification calls retain pending reports as before.

`/docs` and `/openapi.json` provide Spanish descriptions and request/response
examples with the shared error schema. See [integration](integration.md) for
Open311/CSV/session REST and polling limits, [operations](operations.md) for
proxy trust, JSON logging, permissions, backup/restore and retention proposals,
and [demo script](demo-script.md) for synthetic fixtures. The three seeded
before/after comparisons are paired scenes inside the existing single-photo
JPEG; this adds no completion-photo upload endpoint or real repair evidence.

## v0.5 additions: citizen phone verification (no delivery service)

Additive to v0.1–v0.4; staff cookies, CSRF and permissions remain unchanged.
No email, password or real SMS/WhatsApp delivery is introduced.

| Method and path | Request and response |
|---|---|
| `POST /api/citizens/otp/request` | JSON `{phone, device_id}`; `202 {"accepted": true}` for every valid request, including unknown/known phones, cooldown, rate suppression and unavailable delivery. No account existence or delivery result is disclosed. |
| `POST /api/citizens/otp/verify` | JSON `{phone, code, device_id, alias?, alias_public?}`; `200 {"token": "opaque bearer", "expires_at": "UTC ISO 8601"}`. Generic `401 citizen_code_invalid` for unknown, incorrect, expired, exhausted, consumed or wrong-device challenges. Verification rate limit: `429 rate_limited` + `Retry-After`. |
| `POST /api/citizens/logout` | Bearer + `X-Device-ID`; `204`, immediately revokes that device session. Invalid/expired/mismatched credentials: `401 citizen_unauthorized`. |
| `GET /api/citizens/me/reports` | Bearer + `X-Device-ID`; `{items, total, limit, offset}`, newest first; `limit` 1–100 (default 100), `offset` >= 0. Reports owned by this citizen across token rotations and verified devices; excludes hidden reports. Never grants staff access or exposes internal notes. |

`phone` is normalized to E.164 (`+` and 8–15 ASCII digits, first digit nonzero).
A bare eight-digit Guatemala number defaults to country `+502`; a `+502` number
must have exactly eight national digits. Clients generate and securely retain a
random UUID `device_id` before requesting a code. They send the same UUID in
both OTP bodies and in `X-Device-ID` with every bearer-authenticated request,
including report creation. The identifier binds use of the bearer to the client
installation; it is not hardware attestation and theft of both values permits replay.

OTP: six random ASCII digits, valid for ten minutes, at most five failed attempts.
A resend invalidates the old code, is suppressed for 60 seconds and does not reset
the failure budget within an active challenge. Request budgets are three per phone
and ten per direct peer IP per 15 minutes; suppressed requests still return 202.
Verification has independent ten-per-phone and thirty-per-IP budgets per 15 minutes.
All limiter keys containing phone/device information are keyed hashes; client IPs
are never read from untrusted forwarded headers. Limiters reuse the bounded,
per-process sliding-window implementation; deploy a shared edge limiter before scaling.

Tokens contain at least 256 random bits, expire absolutely after 90 days and are
stored only as digests in SQL. Successful verification consumes the challenge and
rotates/revokes any earlier token for that citizen and device. Other verified
devices remain signed in. Phone numbers are stored only as HMAC-SHA256 using
`PHONE_HASH_KEY` plus their last two digits; OTPs are keyed digests, never plaintext
in SQL. `citizen_id` is a nullable internal keyed hash on reports, never serialized
by any public/staff/export endpoint. Anonymous historical reports stay anonymous;
knowing an idempotency key cannot claim ownership of them.

`alias` is optional (1–60 trimmed characters), private by default.
Only explicit `alias_public: true` opts into a public display name; reports created
while opted in may include `citizen_alias`. No number, phone hash, session/device
hash or ownership identifier is returned. The app stores only the masked last-two
digits for profile display, alongside session credentials in secure storage.

`POST /api/reports` accepts `Authorization: Bearer …` + `X-Device-ID` and stores
ownership when authenticated. `REQUIRE_CITIZEN_LOGIN=false` by default preserves
anonymous submission; `true` requires citizen authentication (`401`). Supplied
invalid credentials return 401 even in optional mode. Staff authentication cannot
substitute for citizen authentication. Idempotency remains 24 hours / original
report / 200 on replay; only the same owner (or anonymous-to-anonymous) can replay
an existing key; other owners get `409 idempotency_conflict`, without report data.

Citizen responses use `Cache-Control: no-store`; auth errors use the existing
error envelope and never echo submitted values. JSON validation never logs input.
CORS additionally permits `Authorization` and `X-Device-ID`.

Configuration: `PHONE_HASH_KEY` is a server secret (at least 32 characters), with
an explicitly insecure development fallback only for exact `ENV=dev`. No production
fallback exists. Unconfigured production citizen authentication fails closed;
anonymous report submission remains available when login is optional.
`CITIZEN_SMS_PROVIDER=null` is the default and refuses delivery in every environment.
`console` is accepted only in exact `ENV=dev`: it prints the OTP with a loud DEV
banner in the API log, never the phone number. It sends nothing. Console delivery
must never be enabled with real users. Provider refusal still returns request 202;
verification cannot succeed without a delivered development challenge. Missing production
key configuration returns `503 citizen_unavailable` from verification. See
[the citizen-login decision](decisions/citizen-login.md) for privacy and operational limits.

### Thumbnails and finer clusters (v0.5)

| Method and path | Purpose |
|---|---|
| `GET /api/reports/{id}/thumbnail` | public, same visibility rules as `/photo` (`404` for hidden reports without a staff session; id validated as UUID). JPEG, long edge at most 320 px, quality 72, no EXIF. Generated with Pillow on first request and cached next to the photo (`<id>.thumb.jpg`, atomic write). `Cache-Control: public, max-age=86400`. |

- `thumbnail_url` is `/api/reports/{id}/thumbnail` in every nearby item (`photo_url` keeps pointing to the full photo).
- `GET /api/reports/clusters` uses a finer grid (cell = 360 / 2^(zoom+4) degrees, about 600 m at zoom 12 and 150 m at
  zoom 14) and returns single reports from zoom >= 15 (relaxed from 17). Max 500 items.

## v0.6 additions: Explorar search and pin fields

Additive to v0.1–v0.5; requested by the app (Explorar). Older clients are not affected.

### Text search on `GET /api/reports`

- New optional query parameter `q` (at most 100 characters; blank means no filter). Each word of `q` must match at
  least one of: the category label (`GET /api/categories`), the citizen state label, or the report's `note`.
  Matching is case- and accent-insensitive substring matching (`"revision"` finds *En revisión*, `"danada"` finds
  *Luminaria dañada*, `%` and `_` are literal). Up to eight words are used.
- Citizen state labels are the app's wording (`app/lib/core/citizen_states.dart`, UX decision 4), mirrored in
  `backend/api/app/state_machine.py` as `CITIZEN_STATE_LABELS`; a test keeps both lists equal.
- `q` combines with every other list filter (`bbox`, `category`, `state`, `state_group`, dates, `sort`) and with
  `limit`/`offset`; `total` counts all matches. Hidden reports stay hidden without a staff session.
- `GET /api/reports/clusters`, stats and CSV do not accept `q`.
- Storage: migration `0006` adds `reports.note_search`, a lowercase copy of `note` without accents, filled on every
  note write and backfilled for existing rows. It is never returned by the API.

### Pin fields on one-report clusters

- In `GET /api/reports/clusters`, every cluster with `count == 1` also carries `category`, `state` and `state_group`
  of its report (always the case from zoom 15, where each item is one report). Clusters with `count > 1` keep exactly
  `lat`, `lon`, `count`, `ids`.
