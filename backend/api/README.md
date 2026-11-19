# Aldia API

Python 3.12 / FastAPI public service. The binding interface is
[`documentation/api-contract.md`](../../documentation/api-contract.md).
All public endpoints start with `/api`; OpenAPI is available at `/docs`.

## Install and run

Install uv, then run from `backend/api`:

```sh
uv sync --frozen
# Export deployment configuration in the process environment.
# Local example using a disposable SQLite database:
export DATABASE_URL=sqlite:///./aldia.db
export PHOTO_DIR=/tmp/aldia-api-photos
export VERIFIER_URL=http://127.0.0.1:8001
uv run alembic upgrade head
uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --no-access-log
```

Start the verifier separately (see its README). `make install`, `make migrate`
and `make dev` provide the same workflow, with reload enabled for development.
Python dependencies are pinned in `pyproject.toml`; uv generates `uv.lock`.
Do not edit the lockfile manually. No environment file is loaded automatically.
`.env.example` lists names only; its blank entries are not usable configuration.

| Variable | Default | Meaning |
| --- | --- | --- |
| `DATABASE_URL` | `postgresql+psycopg://aldia:aldia@db:5432/aldia` | Production uses Postgres and psycopg; SQLite is for tests/local development. |
| `PHOTO_DIR` | `/data/photos` | Private directory writable by the service user; never mount it as a static web directory. |
| `VERIFIER_URL` | `http://verifier:8001` | Internal verifier base URL. |
| `MAX_UPLOAD_BYTES` | `8388608` | Maximum original photo bytes (8 MiB). |
| `CORS_ORIGINS` | `http://localhost:5173` | Comma-separated allowed origins. An empty value permits none. |
| `STAFF_TOKEN` | unset | Shared operator credential, at least 32 characters; inject from the secret manager. Unset disables staff endpoints with HTTP 503. |
| `SUPERVISOR_TOKEN` | unset | Optional separate supervisor credential, at least 32 characters, for overrides, closed-case reopening and moderation. |

Override the contract's demonstration database credentials for deployment using
an external secret manager. Keep the verifier and database on a private network.

## Behavior and storage

JPEG/PNG uploads are detected from decoded content. Latitude/longitude must be
finite and in range; timestamps must include a timezone and cannot be more than
60 seconds ahead; category and note length follow the contract. Unknown and
repeated multipart fields are rejected. Query models also reject unknown fields.
The body is bounded before multipart parsing (photo limit plus 64 KiB for fields
and headers), including requests without a Content-Length. Pillow rejects unsafe
decompression sizes and malformed/truncated images.

The service orients the image before removing EXIF, GPS, and all other source
metadata. It stores a fresh JPEG in `PHOTO_DIR/<uuid>.jpg` with an atomic rename.
Paths always validate the UUID first; photos are served only by the report photo
endpoint. If the database commit fails, the new photo is removed. File storage
and SQL are separate resources: a process crash between writing the photo and
committing can leave an orphan file; operators should reconcile UUID files
against reports during maintenance. Back up the database and photo volume together.

The verifier client has a 3-second connect timeout and a 10-second network
operation timeout, no redirects, and no retries. Unreachable, timed-out, non-2xx,
or malformed verifier responses leave the report `pending` with
`verification: null`. This starter has no background retry worker.

For a valid verifier response, the API appends `duplicate`: same category,
64-bit dHash Hamming distance <= 4, and Haversine distance <= 50 metres, compared
against all stored reports with hashes. Duplicates are stored and returned with
HTTP 201 and `status: rejected`, preserving their failed check. On Postgres, a
transaction-level advisory lock serializes duplicate decisions across workers.
The latitude/category index bounds candidates; a spatial index can replace the
prefilter when volume requires it. SQLite does not offer that cross-worker lock
and is not the production database.

A `verified` result in `verification.mode: stub` means the mechanical checks
passed. The category check explicitly says `stub: not classified`; it is not a
trained-model decision. Consumers must display the mode alongside the status.

Responses use UTC ISO 8601 timestamps. Errors use the contract's uniform envelope
and generic Spanish messages; raw exceptions and submitted values are not sent
to clients. Application logs contain no coordinates or request payloads. Supplied
server commands disable access logs because query strings can include a bbox;
configure reverse proxies to avoid logging coordinates as well.

## v0.2 workflow and reads

`status` remains the verifier verdict. Creation records a system event into
`pendiente_verificacion`, then a second event into `nuevo` or
`rechazado_verificador` when the verifier answers; `verified_at` records that
answer even for rejections. A verifier outage leaves one event and no answer date.
`state` drives `state_group` and the legacy `resolution` field (`open`,
`acknowledged`, `fixed`, or the new `closed`). The pure policy table in
`app/state_machine.py` governs every transition, including reason requirements.

Send `X-Staff-Token` on staff requests. Comparisons use `hmac.compare_digest`;
credentials are excluded from settings representations and validation messages.
Missing/wrong credentials return 401 when staff access is configured. Operators
can transition and assign; supervisors can also override verifier rejections,
reopen resolved/closed cases and hide/restore cases. Hiding preserves the previous
state and its resolution/closure clock for restoration. Both credentials are
allowed by CORS and must be supplied by the integrator; compose is unchanged.

- `POST /api/reports/{id}/transition`: `to`, optional `public_note` (280),
  `internal_note` (500), and `duplicate_of` for duplicates. Creates an immutable
  event; reopens clear the resolution/closure timestamp. Duplicate chains are
  flattened and cycles rejected.
- `POST /api/reports/{id}/assign`: `assignee` (60 characters or null). Updates
  `assigned_at` without adding a transition event or changing state.
- Detail responses include events oldest first. Internal notes require valid
  staff credentials. Hidden reports return 404 for public detail/photo reads and
  are excluded from public list, stats, CSV, Open311, clusters and nearby reads.
  Staff detail/list/photo reads can access hidden cases.
- `GET /api/reports/nearby?lat=&lon=&category=&radius_m=150`: up to ten verified,
  open cases of the same category, created in the last 30 days, nearest first.
  Radius is 20–500 m. `GET /api/reports/{id}/nearby` excludes itself and uses 100 m.
  Both return `items`, each with `distance_m` and `thumbnail_url` pointing to the
  existing metadata-stripped photo endpoint. Haversine distance in Python follows
  a SQL bounding-box prefilter, including poles and antimeridian wrap.
- `GET /api/reports/clusters?bbox=&zoom=`: a globally anchored degree grid of
  width `360 / 2**zoom`, single reports at zoom 17–20. Returns at most 500
  clusters with centroids, counts and at most five IDs, plus the full matching
  report total. Payloads contain no photos.
- `GET /api/queue?tab=review|rejected`: requires staff credentials. Review selects
  unassigned `nuevo` cases; rejected selects `rechazado_verificador`. Oldest
  verifier answers come first; items include `age_hours`.

List, statistics, clusters, queue and CSV share category, verifier `status`,
legacy `resolution`, `state`, `state_group`, `assignee`, bbox and creation-date
filters. Creation dates are ISO calendar dates in `America/Guatemala`:
`created_from` is inclusive midnight; `created_to` includes the entire local day.
Without `created_from`, the default is a rolling last 30 days unless
`include_old=true`. List/queue echo `limit` (1–100, default 100) and `offset`.
List and CSV support `sort=newest|oldest|updated|age_in_state`, with UUID tie
breakers. Updated ordering ignores internal-only and moderation events.
Categories also expose their SLA hours and municipal group.

Statistics retain all v0.1 counts with zero keys and add the binding dashboard
formulas. `recibidos` requires an answer date. Resolved and staff-closed totals
use their event dates in the selected period, including cases created earlier;
other metrics use the creation cohort. `tasa_resolucion` is a percentage of
currently resolved cases created in the cohort divided by received cases minus
duplicates and out-of-jurisdiction cases; `tasa_resolucion_n` is that denominator.
Resolution durations and SLA use cases resolved in the period. SLA is a fraction
from 0 to 1; empty denominators return null. First response uses the first
non-system state change or public message. P90 uses linear interpolation at
`(n - 1) * 0.9`. Age buckets use completed days; weekly ISO week labels use local
time, with received cases grouped by creation and resolutions by resolution.

CSV accepts `delimiter=comma|semicolon`, includes a UTF-8 BOM and the columns:
`id,created_at,verified_at,category,state,state_changed_at,resolved_at,latitude,longitude,assignee,verifier_status,duplicates_count,days_open,link`.
The export cap remains 5000 rows. Formula protection applies to text cells only;
negative numeric coordinates stay numeric. Duplicate counts exclude hidden
cases. Days open runs from verifier answer to resolution/closure (or now for an
open case); pending cases have an empty value. Links target the report endpoint.

Open311 remains read-only, verified-only and capped at 1000, with its original
service/date/status filters and no implicit 30-day window. Groups `resolved` and
`closed` map to `closed`, others to `open`; `updated_datetime` uses the state
change date. Photo URLs and requested timestamps retain their v0.1 meaning.

## App retries

`POST /api/reports` accepts a UUID `Idempotency-Key`. Keys are persisted in SQL
in the same transaction as the report and creation events. Replays within 24 h
return the existing report with 200, creating neither a report nor a photo.
Expired keys are purged on subsequent creation and may be reused. A process lock
serializes local SQLite creation; the Postgres advisory transaction lock covers
multiple workers. The key is checked again under that lock before verification.
A replay returns the report's current representation, including public events.
If moderation has hidden it, replay returns 404 and still creates nothing.

## Migrations

Schema creation is explicit; application startup never creates tables:

```sh
uv run alembic upgrade head
uv run alembic check
# After editing mapped schema, generate and review a migration:
uv run alembic revision --autogenerate -m "describe schema change"
```

Run migrations once as a deployment step before starting API replicas. The
initial migration has a downgrade; downgrading to `base` deletes reports. Test on
a disposable database and keep backups before production schema changes.
Migration `0002` adds a non-null resolution with a database default of `open`
(including existing reports) and a constraint for the three allowed values.
Downgrading to `0001` preserves reports but removes their resolution state.
Migration `0003` adds case states, timestamps, assignment, duplicate linkage,
audit events, retry keys and query indexes. Existing pending/rejected verdicts
map to their system states; verified fixed/acknowledged/open rows map to
`resuelto`/`en_proceso`/`nuevo`. Historical clocks are unavailable: the migration
uses `created_at` as an approximation and records this in a system event's
internal note. Downgrade removes v0.2 history and maps `closed` resolution to
`open` to restore the v0.1 constraint. Migration round trips and schema drift are
tested on SQLite; live Postgres migration execution is a deployment check.

## Verify

```sh
uv sync
uv run ruff check
uv run ruff format --check
uv run mypy app
uv run pytest
```

`make test`, `make lint` (including strict mypy), and `make fmt` are also available.
Tests use temporary SQLite databases, synthetic in-memory images and an httpx
fake verifier; they do not read local environment files or personal photos.
They cover the public contract, validation, metadata removal, duplicates, failed
verifier calls, upload limits, persistence failure cleanup and migration drift.
The v0.1 tests also cover resolution, shared read filters, zero-filled statistics,
UTF-8 CSV shape and injection protection, both export caps, Open311 field mapping
and visibility, and migration of existing reports.

## Container

From this directory:

```sh
docker build -t aldia-api .
# Supply configuration from your deployment environment and a writable photo
# volume owned by UID/GID 10001. Run migrations once on the same configuration:
docker run --rm --network aldia --env DATABASE_URL aldia-api uv run --no-sync alembic upgrade head
docker run --rm --network aldia -p 8000:8000 --env DATABASE_URL --env VERIFIER_URL \
  --mount type=volume,src=aldia-photos,dst=/data/photos aldia-api
```

The multi-stage image uses a frozen production-only uv environment, runs as
UID/GID 10001, and checks `/api/health`. Health is a liveness check, not a promise
of database or verifier availability. The shared staff-token scheme is a v0.2 stopgap; use only synthetic or
explicitly consented photos for this PoC.
