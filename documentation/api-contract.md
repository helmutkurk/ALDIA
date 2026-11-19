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
| `GET /api/health` | `{"status": "ok"}` |
| `GET /api/categories` | `[{"id": "pothole", "label": "Bache"}]` |
| `POST /api/reports` | `multipart/form-data`: `photo` (JPEG or PNG, max 8 MB), `category`, `latitude`, `longitude`, `captured_at`, optional `note` (max 280). Returns `201` + report. The API calls the verifier, adds the `duplicate` check and stores the result. |
| `GET /api/reports` | Query: `bbox=min_lon,min_lat,max_lon,max_lat`, `category`, `status`, `limit` (1-500, default 100), `offset`. Returns `{"items": [report], "total": 0}` newest first. |
| `GET /api/reports/{id}` | One report, `404` if unknown. |
| `GET /api/reports/{id}/photo` | Stored photo (EXIF and GPS removed), `image/jpeg`. |
| `GET /api/stats` | v0.1, for the portal dashboard: `{"total": 0, "by_category": {"pothole": 0}, "by_status": {"verified": 0}, "by_resolution": {"open": 0}}`. Same optional filters as the list (`bbox`, `category`, `status`, `resolution`). |
| `GET /api/reports.csv` | v0.1, CSV export with the same filters: `id,category,latitude,longitude,captured_at,created_at,status,resolution,photo_url`. |
| `GET /api/open311/v2/requests.json` | v0.1, read-only Open311 GeoReport v2 view of verified reports: `service_request_id`, `status` (`open` or `closed`, closed when `resolution` is `fixed`), `service_code` (category id), `service_name` (label), `description` (note), `lat`, `long`, `requested_datetime`, `updated_datetime`, `media_url`. |

The list also accepts `resolution=open|acknowledged|fixed`.

Rules: the API strips EXIF before storing; it never logs coordinates with a worker identity; ids are validated as UUIDs
before any path use. There is no authentication in v0: the PoC shows synthetic or consented photos only. Deciding
auth (citizen device, government portal login) is an open decision (`documentation/decisions/`).

## Verifier API (`backend/verifier`)

`GET /health` returns `{"status": "ok", "mode": "stub"}`.

`POST /verify` (`multipart/form-data`: `photo`, `category`, `latitude`, `longitude`, `captured_at`) returns:

```json
{
  "passed": true,
  "mode": "stub",
  "phash": "f0e4c2a1b3d5978f",
  "checks": [
    {"name": "image", "passed": true, "detail": "1280x960 jpeg"},
    {"name": "place", "passed": true, "detail": "inside GT"},
    {"name": "freshness", "passed": true, "detail": "age 5 s"},
    {"name": "category", "passed": true, "detail": "stub: not classified"}
  ]
}
```

`phash` is a 64-bit difference hash as 16 hex characters. The API compares it with stored reports of the same category
(Hamming distance <= 4 within 50 m) and appends the `duplicate` check. Checks: `image` (decodes, min 640x480),
`place` (inside the bounding boxes of Guatemala, Colombia or Mexico), `freshness` (captured within
`MAX_AGE_SECONDS`, default 600, and not more than 60 s in the future), `category` (classifier; the stub accepts and
says it did not classify). `mode` is `stub` or `model`; a stub result is never presented as real verification.

## Configuration (environment variables)

| Service | Variable | Default |
|---|---|---|
| api | `DATABASE_URL` | `postgresql+psycopg://aldia:aldia@db:5432/aldia` |
| api | `PHOTO_DIR` | `/data/photos` |
| api | `VERIFIER_URL` | `http://verifier:8001` |
| api | `MAX_UPLOAD_BYTES` | `8388608` |
| api | `CORS_ORIGINS` | `http://localhost:5173` |
| verifier | `VERIFIER_MODE` | `stub` |
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
| `GET /api/reports/clusters` | `bbox` (required), `zoom` (0-20). Grid-clustered pins: `{"clusters": [{"lat","lon","count","ids"?: [first 5 ids]}], "total"}`. At zoom >= 17 returns single reports. Max 500 items. Light payload (no photos). |
| `GET /api/queue` | staff-friendly triage list: `?tab=review|rejected`; `review` = state `nuevo` and no assignee, oldest `verified_at` first, each with `age_hours`; `rejected` = state `rechazado_verificador`. Same pagination as the list. |

### List, stats and export changes

- `GET /api/reports` new filters: `state`, `state_group`, `assignee`, `created_from`, `created_to` (ISO dates),
  `sort` (`newest` default, `oldest`, `updated`, `age_in_state`), `limit` (max 100 when paginating), `offset`. Response adds
  `"limit"` and `"offset"` echo fields. Default window without `created_from`: last 30 days unless `include_old=true`.
- `GET /api/stats` adds (same filters, municipality day boundaries `America/Guatemala`):
  `recibidos`, `rechazados_verificador`, `abiertos`, `resueltos`, `cerrados_sin_solucion`, `tasa_resolucion` (resueltos created in
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
window uses `America/Guatemala` day boundaries and defaults to the last 30 days. Pagination and `sort` do not
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
