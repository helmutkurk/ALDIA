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

## v0.1 read endpoints

Every report includes `resolution`: `open` (default), `acknowledged`, or `fixed`.
It tracks government handling separately from verification `status`. There is
no public endpoint or create field for setting resolution yet.

The list (`GET /api/reports`), statistics and CSV export share the same optional
filters: `bbox=min_lon,min_lat,max_lon,max_lat`, `category`, `status`
(`pending|verified|rejected`) and `resolution` (`open|acknowledged|fixed`).
Filters combine with AND; bbox edges are inclusive. Only the list accepts
`limit` (1–500, default 100) and `offset` (default 0).

- `GET /api/stats` returns `total`, `by_category`, `by_status` and `by_resolution`.
  Every known category, status and resolution key is present, including zeros.
  Counts cover all matching reports, without pagination or export caps.
- `GET /api/reports.csv` returns UTF-8 CSV with the header
  `id,category,latitude,longitude,captured_at,created_at,status,resolution,photo_url`
  and `Content-Disposition: attachment; filename=aldia-reports.csv`.
  It returns at most 5000 matching rows, newest first (UUID descending breaks
  timestamp ties), using the same ordering as the list. Every cell starting
  with `=`, `+`, `-` or `@` is prefixed with a single quote to prevent spreadsheet
  formula injection; this also applies to negative coordinates. CSV quoting
  preserves commas, quotes, newlines and accented characters.
- `GET /api/open311/v2/requests.json` is a read-only GeoReport v2 view containing
  at most 1000 **verified** reports, newest first with the same tie ordering.
  Optional filters are `service_code` (category ID), `status` (`open|closed`),
  `start_date` and `end_date` (timezone-aware ISO 8601 timestamps, inclusive).
  Date filters apply to `created_at`; reversed ranges are rejected.

Open311 maps the UUID to `service_request_id`, category ID/Spanish label to
`service_code`/`service_name`, note to `description` (empty string when absent),
coordinates to `lat`/`long`, and the photo endpoint to `media_url`.
`resolution: fixed` maps to `status: closed`; `open` and `acknowledged` map to
`status: open`. Rejected and pending reports are always excluded. Both
`requested_datetime` and `updated_datetime` use `created_at` because reports
cannot be updated through the API yet. Media URLs are relative to this server,
matching `photo_url`. No Open311 write endpoints are provided.

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
of database or verifier availability. Authentication is intentionally absent in
contract v0.1; use only synthetic or explicitly consented photos for this PoC.
