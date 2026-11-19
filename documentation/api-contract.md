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
