# Municipal integration call sheet

Use HTTPS for a deployed API. Replace `https://aldia.example` below with the
municipality's origin; local development uses `http://127.0.0.1:8000`.
`GET /docs` is the interactive reference; `GET /openapi.json` is the machine-readable
contract. Examples here use synthetic reports. Category IDs are stable.

## Public reads and Open311

```sh
curl --fail --silent --show-error https://aldia.example/api/health
curl --fail --silent --show-error https://aldia.example/api/categories
curl --fail --silent --show-error \
  https://aldia.example/api/open311/v2/services.json
curl --fail --silent --show-error --get \
  https://aldia.example/api/open311/v2/requests.json \
  --data-urlencode service_code=pothole --data-urlencode status=open \
  --data-urlencode start_date=2026-09-20T00:00:00Z \
  --data-urlencode end_date=2026-11-20T23:59:59Z
```

`services.json` returns all six categories with `service_code`, `service_name`,
`description`, `metadata: false`, `type: "realtime"`, `keywords` and `group`.
`requests.json` returns a JSON array of verified, publicly visible reports:

```json
{
  "service_request_id": "8d231ed0-b858-4bd5-bf2e-c8c5a4d2dd01",
  "status": "open",
  "service_code": "pothole",
  "service_name": "Bache",
  "description": "[demo] Bache junto al cruce.",
  "lat": 14.6349,
  "long": -90.5069,
  "requested_datetime": "2026-11-20T12:00:00Z",
  "updated_datetime": "2026-11-20T12:00:00Z",
  "media_url": "/api/reports/8d231ed0-b858-4bd5-bf2e-c8c5a4d2dd01/photo"
}
```

Resolve relative `media_url` against the API origin. Resolved and closed cases
map to Open311 `closed`; others map to `open`. This is a **read-only GeoReport v2
view**, not a complete Open311 implementation: there is no Open311 create,
service-definition, discovery or single-request endpoint. Dates filter report
creation, not changes. At most 1000 rows are returned, newest first, with no
pagination. Split queries by creation dates/category when needed; a result of
1000 rows is potentially truncated. Use REST pagination for complete exports.

## CSV and REST reads

```sh
curl --fail --silent --show-error --get \
  https://aldia.example/api/reports.csv \
  --data-urlencode include_old=true --data-urlencode delimiter=semicolon \
  --output aldia-reports.csv
curl --fail --silent --show-error --get \
  https://aldia.example/api/reports \
  --data-urlencode include_old=true --data-urlencode sort=oldest \
  --data-urlencode limit=100 --data-urlencode offset=0
curl --fail --silent --show-error \
  'https://aldia.example/api/stats?include_old=true'
```

CSV uses UTF-8 with a byte order mark (BOM), protects text cells against spreadsheet
formula injection, and supports `delimiter=comma|semicolon`. Columns:
`id,created_at,verified_at,category,state,state_changed_at,resolved_at,latitude,longitude,assignee,verifier_status,duplicates_count,days_open,link`.
It excludes hidden reports and internal notes and caps output at **5000 rows**.
Partition by `created_from`/`created_to` and category if a download reaches the cap.
An individual day/category above that cap needs REST pagination.

REST returns `items`, `total`, `limit`, `offset`; use a limit of 1–100 and advance
the offset until all items have been read. Without `created_from` or
`include_old=true`, the default window is the last 30 days. REST date filters use
inclusive calendar dates in `America/Guatemala`; Open311 uses timezone-aware
ISO 8601 timestamps. The same category/state/date/bounding-box filters apply to
CSV and statistics. A bounding box is `west,south,east,north`.

## REST with a staff session

Staff accounts use roles `operator`, `supervisor`, `admin`. Bootstrap the first
admin with the API CLI; create named operator accounts through the admin API.
There is no fixed deployment password. Login sets `aldia_session` (HttpOnly) and
`aldia_csrf`; writes require an `X-CSRF-Token` header matching the CSRF cookie.
Cookies are Secure outside exact `ENV=dev`, SameSite=Lax, and expire absolutely
after 12 hours. Session revocation is stored in SQL. Auth responses are no-store.

This Python 3 standard-library example keeps credentials/cookies in memory,
prompts privately for the password and never prints them. Run it against a
disposable synthetic case currently in `nuevo`; `nuevo` → `en_revision` is valid.
A 409 means the state has changed or the transition is not permitted.

```python
import getpass
import http.cookiejar
import json
import urllib.error
import urllib.request
from uuid import UUID

origin = "https://aldia.example"
jar = http.cookiejar.CookieJar()
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def call(method, path, data=None, csrf=False):
    headers = {"Content-Type": "application/json"}
    if csrf:
        headers["X-CSRF-Token"] = next(c.value for c in jar if c.name == "aldia_csrf")
    request = urllib.request.Request(
        origin + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers=headers,
        method=method,
    )
    with client.open(request, timeout=20) as response:
        return json.load(response) if response.status != 204 else None


logged_in = False
try:
    call("POST", "/api/auth/login", {
        "username": input("Staff username: "),
        "password": getpass.getpass("Staff password: "),
    })
    logged_in = True
    identity = call("GET", "/api/auth/me")
    report_id = str(UUID(input("Synthetic report UUID in nuevo: ")))
    call("POST", f"/api/reports/{report_id}/assign", {
        "assignee": "Cuadrilla Centro",
    }, csrf=True)
    changed = call("POST", f"/api/reports/{report_id}/transition", {
        "to": "en_revision",
        "public_note": "Recibimos su reporte y lo estamos revisando.",
    }, csrf=True)
    print("Case state:", changed["state"])
except urllib.error.HTTPError as error:
    print("API status:", error.code)  # Never log the request, cookies or password.
finally:
    if logged_in:
        call("POST", "/api/auth/logout", csrf=True)
```

Continue with legal transitions `en_revision` → `programado` → `en_proceso` →
`resuelto`, adding a public note such as `Cuadrilla programada para el jueves.`
Reopening/overriding rejected or closed cases requires supervisor/admin permissions;
see [the state table](api-contract.md#case-state-machine).
Assignment is a current field; it does not create a timeline event.

For a browser on a separate origin, allow its exact origin through `CORS_ORIGINS`
and send credentials with requests. CORS is a browser policy, not API
authentication. Do not put staff credentials in URLs or browser storage.
Cross-site embedding is constrained by SameSite=Lax; prefer a same-site portal.
The legacy staff-token header is a dev-only compatibility option, not an IT
integration credential for deployment.

## Polling without webhooks

There are no webhook registrations, change cursor or `updated_since` filter.
For a pilot, poll every 60 seconds:

1. Fetch `/api/reports?include_old=true&sort=updated&limit=100&offset=0`, then every
   page. Upsert by `id`; compare `state`, `state_changed_at`, `assignee` and other
   needed fields against the local copy. Fetch individual detail for its timeline.
2. Keep previously known unresolved IDs and re-fetch their details to catch
   changes to reports older than the default 30-day window. Persist the last
   successful completed scan and retry incomplete pages.
3. Repeat a complete reconciliation periodically. Offset pagination is not a
   snapshot: changes during scanning can shift rows, so deduplicate IDs and
   repeat scans. `sort=updated` orders public timeline activity; assignment
   changes do not create events, so do not stop at a timestamp watermark.
4. An absent report/404 may be hidden, unavailable to the caller, or missing;
   avoid inferring a deletion from a single scan. Define local visibility and
   reconciliation rules with the municipality. A public scan cannot retrieve
   hidden cases; staff reads need an authenticated session.

Open311 creation-date filtering cannot reliably discover later closures of older
cases. Do not use its `start_date` as a modification cursor. This polling scheme
provides eventual reconciliation for a modest pilot, without exactly-once or
snapshot guarantees. Agree an incremental synchronization contract before a
large production integration.

## Errors and operating limits

Errors use `{"error":{"code":"validation_error","message":"Solicitud inválida."}}`.
The health readiness response deliberately uses `status` and `dependencies`,
returning 503 if any dependency is unavailable. Report creation remains available
during a verifier outage: it stores `status: "pending"`, `verification: null`;
there is no background retry worker.

Handle 401 by logging in again, 403 by checking role/CSRF, 409 by fetching the
latest report, 413 by reducing the body/photo size, 422 by fixing input, and 429
by waiting the numeric `Retry-After` seconds. Five failed staff logins lock an
account for 15 minutes (423); do not blindly retry. Public POST rate limits are
per direct peer IP, in-memory per process; login also has its existing
username/IP limiter. See [operations](operations.md) for proxy configuration,
body limits, backup/restore and privacy constraints. Verifier decisions expose
mechanical checks and mode; they are not proof that a street problem exists.
