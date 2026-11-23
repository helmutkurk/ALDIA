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
export ENV=dev       # local HTTP cookies only; production requires HTTPS
export CITIZEN_SMS_PROVIDER=console  # synthetic citizen login, prints DEV code locally
uv run alembic upgrade head
uv run python -m app.cli create-admin --username admin  # hidden password prompt, min 12 characters
uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000 --no-access-log --no-server-header --no-proxy-headers
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
| `MAX_REQUEST_BYTES` | `65536` | Maximum other POST/PUT/PATCH body bytes, including JSON staff writes. |
| `PUBLIC_POST_RATE_LIMIT` | `60` | Combined public report/login POST budget per direct peer IP per process. |
| `PUBLIC_POST_WINDOW_SECONDS` | `60` | Sliding-window duration; 429 returns `Retry-After`. |
| `VERIFIER_TIMEOUT_SECONDS` | `10` | Per-network-operation verification timeout; connect at most 3 seconds. |
| `CORS_ORIGINS` | `http://localhost:5173` | Comma-separated exact HTTP(S) origins, no wildcard/path/trailing slash. Empty permits none. |
| `ENV` | `production` | Only exact `dev` disables Secure cookies and permits demo accounts. |
| `PHONE_HASH_KEY` | unset | External HMAC secret, at least 32 characters; insecure fallback only with exact `ENV=dev`. |
| `CITIZEN_SMS_PROVIDER` | `null` | Refuses delivery; `console` only with `ENV=dev`, logs a DEV code without the phone, sends nothing. |
| `REQUIRE_CITIZEN_LOGIN` | `false` | Require citizen bearer + installation id for report creation; production requires a configured HMAC secret. |
| `AUTH_DEV_TOKENS` | `false` | Legacy header fallback requires both this flag and `ENV=dev`; every attempt logs a credential-free warning. |
| `STAFF_TOKEN` | unset | Legacy dev-only operator credential, at least 32 characters. Never needed for account login. |
| `SUPERVISOR_TOKEN` | unset | Legacy dev-only supervisor credential, at least 32 characters. |

Override the contract's demonstration database credentials for deployment using
an external secret manager. Keep the verifier and database on a private network.
If uv's default cache is read-only, set `UV_CACHE_DIR=/tmp/aldia-uv-cache`.

See [operations and data handling](../../documentation/operations.md) for deployment,
rate-limit/proxy boundaries, consistent backup and isolated restore drills, and
proposed retention. The [integration call sheet](../../documentation/integration.md)
covers Open311, CSV, session-authenticated REST and polling. `/docs` and
`/openapi.json` include Spanish descriptions, examples and uniform error schemas.

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
The service enforces photo-directory mode `0700` on write/health checks, with
new JPEGs mode `0600`; provision an owned directory for the service account.

The verifier client defaults to a 3-second connect timeout and a 10-second network
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
Application records are JSON lines; request records include only method, route
template, status and elapsed milliseconds, without IP, raw URL, body or identity.
All responses carry `nosniff`, `no-referrer` and restrictive API Permissions-Policy
headers; supplied server commands disable the Uvicorn server banner.
Public report/login POSTs share the configurable in-memory per-IP budget above;
invalid submissions count too. It resets on restart and is not shared across
workers. Forwarded headers are disabled by supplied launch commands; configure a
trusted ingress and shared edge limiter before scaling (see the runbook).

## v0.2 workflow and reads

`status` remains the verifier verdict. Creation records a system event into
`pendiente_verificacion`, then a second event into `nuevo` or
`rechazado_verificador` when the verifier answers; `verified_at` records that
answer even for rejections. A verifier outage leaves one event and no answer date.
`state` drives `state_group` and the legacy `resolution` field (`open`,
`acknowledged`, `fixed`, or the new `closed`). The pure policy table in
`app/state_machine.py` governs every transition, including reason requirements.

Staff accounts replace the v0.2 shared token; see the [v0.4 decision](../../documentation/decisions/staff-auth.md).
Log in through the portal's **Modo personal** with username/password. The API returns
the real username and role, sets an HttpOnly session cookie and a readable CSRF cookie,
and stores a revocable 12-hour session in SQL. Staff writes send `X-CSRF-Token` matching
the cookie and session. No credentials go in browser storage. Missing/expired sessions
return 401, insufficient role or CSRF 403, and locked accounts 423.
Operators transition and assign; supervisors also override, reopen and moderate;
admin inherits those rights and alone manages `/api/admin/users` (GET/POST/PATCH).
User changes revoke all target sessions; password resets also clear lockout.
Report events retain `actor_role` and add `actor`; auth/user changes have a separate audit table.
Hiding preserves the previous state and resolution/closure clock for restoration.

Passwords use pinned argon2-cffi with explicit Argon2id v19 parameters (64 MiB, 3 passes,
4 lanes, 16-byte salt, 32-byte hash). Five failures lock the SQL account for 15 minutes;
unknown/disabled users receive generic errors and still perform password verification.
An in-memory limiter allows 10 login requests per normalized username + direct peer IP
per 15 minutes, retaining at most 10,000 keys. Limits reset on restart, are not shared
across workers, and old keys may be evicted under churn. Use a shared edge limiter before
multi-worker deployment; forwarded IP headers are not trusted by application code.
SQLite login serialization is per process; production PostgreSQL uses row locks.

Serve the portal and API under the same origin through `/api` so JavaScript can read
the CSRF cookie; use HTTPS outside `ENV=dev`. CORS allows explicit origins, credentials,
PATCH and `X-CSRF-Token`. Login validates supplied Origin. For a non-interactive admin
bootstrap, pipe the password from a secret manager to `uv run python -m app.cli create-admin`.
Never pass it in argv. The CLI rejects duplicates and passwords shorter than 12 characters.

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
  width `360 / 2**(zoom+4)`, single reports at zoom 15–20. Returns at most 500
  clusters with centroids, counts and at most five IDs, plus the full matching
  report total. One-report clusters also carry `category`, `state` and
  `state_group` (v0.6). Payloads contain no photos.
- `GET /api/reports?q=`: case- and accent-insensitive text search over category
  label, citizen state label and note; every word must match (v0.6, migration
  `0006` adds the folded `note_search` column).
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
other metrics use the creation cohort. `tasa_resolucion` is a ratio from 0 to 1 of
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
`GET /api/open311/v2/services.json` lists all six stable category service codes,
Spanish names/descriptions, `metadata: false`, `type: realtime` and group labels.

## App retries

`POST /api/reports` accepts a UUID `Idempotency-Key`. Keys are persisted in SQL
in the same transaction as the report and creation events. Replays within 24 h
return the existing report with 200, creating neither a report nor a photo.
Expired keys are purged on subsequent creation and may be reused. A process lock
serializes local SQLite creation; the Postgres advisory transaction lock covers
multiple workers. The key is checked again under that lock before verification.
A replay returns the report's current representation, including public events.
If moderation has hidden it, replay returns 404 and still creates nothing.

## Demo data

`scripts/seed_demo.py` creates 62 synthetic reports (60 public) in a compact Zona 4
neighborhood in Guatemala City: all categories and 11 states over 60 days, a growing
weekly cumulative resolved share, duplicate links and explained verifier rejections.
Three stable fixed cases show paired synthetic ANTES/DESPUES scenes in the existing
800x600 JPEG photo; a separate completion-photo upload is not implemented.
It writes through the SQLAlchemy models and
`PhotoStorage`, marks every row with a note starting `[demo]`, and uses deterministic ids, so repeated runs create
nothing new. It refuses production flags including `ENV=production`.
Use `--reset` to replace an older seed: idempotence preserves existing row content.
See the [five-minute demo script](../../documentation/demo-script.md) for exact
UI actions, stable report links, weekly figures and limits of the synthetic evidence.
Only `ENV=dev` creates `operador`/`supervisor` accounts with random initial passwords
printed once when each account is created. No fixed credentials exist. Reruns preserve
passwords; `--reset`/`--purge` affect reports only. Capture initial output privately and
avoid seed log capture in shared environments. See [demo credentials](../../documentation/demo-credentials.md).

```sh
export ENV=dev DATABASE_URL=sqlite:///./aldia.db PHOTO_DIR=/tmp/aldia-api-photos
uv run alembic upgrade head
uv run python scripts/seed_demo.py            # create what is missing
uv run python scripts/seed_demo.py --reset    # delete "[demo]" rows, then create again
uv run python scripts/seed_demo.py --purge    # delete "[demo]" rows only
```

From the repo root: `make seed` and `make seed-reset`. Tests: `tests/test_seed_script.py`.

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
Migration `0004` adds staff users/sessions/auth audit and report event actors. Existing
non-system events become `legacy:<role>`; no historical identity is invented. Downgrade
removes accounts, sessions, auth audit and actor attribution; back up before using it.

## Verify

```sh
uv sync
uv run ruff check
uv run ruff format --check
uv run mypy app
uv run pytest
```

`make test`, `make lint` (including strict mypy), and `make fmt` are also available.

The same suite runs against PostgreSQL when `TEST_POSTGRES_URL` points to the admin
database of a disposable server; each test gets a fresh database that is dropped
afterwards (`tests/conftest.py`). Never point it at a server with real data:

```sh
docker run -d --name aldia-pg-test -e POSTGRES_USER=aldia -e POSTGRES_PASSWORD=test-only \
  -p 127.0.0.1:55432:5432 postgres:17-alpine
TEST_POSTGRES_URL=postgresql+psycopg://aldia:test-only@127.0.0.1:55432/postgres uv run pytest
docker rm -f aldia-pg-test
```

Without the variable, tests use temporary SQLite databases, synthetic in-memory images and an httpx
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
UID/GID 10001, and checks `/api/health`. Health now checks SQL connectivity, verifier `/health` and writable
photo storage. HTTP 200 returns `{"status":"ok","dependencies":{"database":"ok","verifier":"ok","photos":"ok"}}`;
any failed dependency returns 503 with `status: degraded` and that dependency
`unavailable`. Use it for readiness/alerting, keeping process liveness separate.
Use HTTPS and real staff accounts for deployments; keep the legacy fallback
disabled. The verifier is heuristic with category classification still a stub;
demo photos and recorded demo verdicts are synthetic.


## Citizen login quick start (v0.5, no real delivery)

Apply `uv run alembic upgrade head` before restarting the API (migration `0005`).
Start with `ENV=dev CITIZEN_SMS_PROVIDER=console` as above. In the app submit step
choose to verify a synthetic Guatemala number, then read the six-digit code privately
from the API log's **DEV ONLY — NO SMS SENT** banner. It is valid ten minutes,
with five failed attempts and a 60-second resend cooldown. Never paste the code,
number or token into an issue, shared log or screenshot. No SMS is sent.

The app defaults to optional login and **Continuar sin avisos**. For mandatory login,
set API `REQUIRE_CITIZEN_LOGIN=true` and run the app with the matching
`--dart-define=REQUIRE_CITIZEN_LOGIN=true`. Profile displays a masked verified number
and logout. Authenticated report creation uses `Authorization: Bearer …` and
`X-Device-ID`; **Mis reportes** combines local and server-owned reports. Real-time
push remains unimplemented. Anonymous local reports are never automatically claimed.

Production defaults to the null provider. Without a configured key, valid requests
still return 202 and verification returns 503. With a key but no delivery provider,
requests return 202 and no usable challenge is created. No production phone login
is available until the team selects and implements a real provider.
See [contract v0.5](../../documentation/api-contract.md#v05-additions-citizen-phone-verification-no-delivery-service)
and [privacy/operations decision](../../documentation/decisions/citizen-login.md).
Migration downgrade to `0004` preserves report content but removes citizen identities,
challenges, sessions, ownership and aliases. Back up before downgrading.
