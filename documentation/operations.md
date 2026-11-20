# API operations and data handling

This runbook covers the current single-process demonstration and a proposed pilot.
A successful local demo is not evidence of production capacity or a recovery SLA.
Use the [integration call sheet](integration.md) for requests and the
[demo walkthrough](demo-script.md) for synthetic fixtures.

## Service boundary and configuration

Run the API as an unprivileged service account behind HTTPS, with PostgreSQL and
verifier reachable only on a private network. Provision deployment credentials
through a secret manager. Disable development authentication in deployments
(`ENV=production`, `AUTH_DEV_TOKENS=false`). Migrate before starting replicas.

Set `CORS_ORIGINS` to comma-separated exact origins, including scheme and port,
for example `https://reportes.example.org,https://gestion.example.org`. Wildcards,
credentials in origins, paths, trailing slashes and `null` are rejected at startup;
an empty string permits no cross-origin reads. Prefer serving portal and `/api`
on one origin for session/CSRF cookies. CORS is a browser policy, not authentication.

Public POSTs to `/api/reports` and `/api/auth/login` share a sliding-window budget
per direct peer IP: `PUBLIC_POST_RATE_LIMIT=60` over
`PUBLIC_POST_WINDOW_SECONDS=60`. Invalid requests and retries consume budget;
GETs and authenticated staff actions do not. HTTP 429 carries a numeric
`Retry-After`. The existing username+IP login limit and SQL account lockouts still
apply. The limiter is in memory, per process, clears on restart, and retains at
most 10,000 active IP buckets; new peers are refused until capacity expires.
A shared address (office or mobile carrier) shares its budget. Configure limits
for the pilot and add a shared ingress limiter before scaling to multiple workers.

Application code ignores forwarded IP headers. Supplied API/verifier Makefile and
container commands use `--no-proxy-headers`, `--no-access-log` and
`--no-server-header`. With a reverse proxy this groups clients under the proxy IP.
To preserve client budgets, explicitly enable Uvicorn proxy handling with
`--proxy-headers --forwarded-allow-ips=<trusted-proxy-IP>` and firewall direct API
access; the trusted proxy must replace incoming forwarding headers. Never trust
all forwarding sources. Apply equivalent settings to custom launchers, including
root development scripts. Remove proxy/framework banners at the ingress too.

All API responses, including errors and CORS preflights, carry
`X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, and
`Permissions-Policy: camera=(), microphone=(), geolocation=()`. This policy belongs
to API responses; keep the citizen app's own camera/location permissions on its
own origin. Uvicorn's banner is disabled by the supplied launch commands.

`MAX_UPLOAD_BYTES` defaults to 8 MiB for an individual photo. Report request bodies
are bounded before multipart parsing at that limit plus 64 KiB. Other POST/PUT/PATCH
bodies are bounded by `MAX_REQUEST_BYTES` (default 64 KiB). Streaming bodies are
counted even without Content-Length. A reverse proxy should also enforce body,
request-duration and connection limits; the process limiter is not DDoS protection.

## Health, logs and pending reports

`GET /api/health` performs `SELECT 1`, calls verifier `/health` (one-second network
operation timeout), and creates/writes/removes a temporary file in `PHOTO_DIR`.
HTTP 200 has `status: ok`; any failed dependency yields HTTP 503 with
`status: degraded` and individual `database`, `verifier`, `photos` values of `ok`
or `unavailable`. Responses are not cached and reveal no URLs, paths or exceptions.
This checks database connectivity, not migration completeness or model quality.
PostgreSQL connection/pool acquisition timeouts are three seconds; an established
but stalled SQL connection still requires infrastructure timeouts/monitoring.
Do not restart a healthy API solely because the verifier is down: writes can still
be retained pending. Configure an ingress readiness check separately from process
liveness, and alert on dependency degradation.

The verifier client has no redirects/retries and uses
`VERIFIER_TIMEOUT_SECONDS=10` per network operation (connect at most three seconds).
Outage, timeout or invalid response retains the report as `pending` with
`verification: null`; it does not invent a verdict. These are network-operation
timeouts, not a total request deadline. There is no automatic retry worker.
Monitor pending cases and plan a reviewed recovery/reverification workflow.

Application logs are JSON lines with time, level and event. HTTP request events
add only method, route template, response status and elapsed milliseconds. They
exclude raw paths/UUIDs, IPs, query strings, coordinates, request bodies, notes,
cookies, authorization data and exception text. Do not enable access/debug logs
that undo this policy. The SQL auth audit is separate and deliberately attributes
staff actions. Restrict log access and rotation; configure ingress logs to omit
query strings and credentials. The console's Uvicorn lifecycle messages are
operational server output, separate from application JSON request logs.

## Photo volume

Use a dedicated persistent `PHOTO_DIR`, owned by the API service account. The API
creates it and enforces mode `0700` on writes and health probes; atomic temporary
files produce `0600` JPEGs. Existing directories must be owned by that account so
it can enforce the mode. Never expose the volume as a static directory. Backups
and restored volumes require the same restrictions. The container uses UID/GID
10001. Audit pre-existing files after a migration: health checks do not chmod every
old file. The service orients images and re-encodes fresh JPEGs without EXIF/GPS
or other source metadata. Visible faces, plates and private text are not removed.

## Consistent backup

Choose and record a recovery point objective (proposed pilot: daily backups,
24-hour maximum loss) and a recovery time target after an actual restore drill.
Keep encrypted, access-controlled copies off the application host. Proposed
backup retention: 30 daily snapshots. Credentials must be supplied privately by
the operator; never put passwords in commands, archives or this repository.

Stop all writers first: API replicas, seed jobs, maintenance jobs and any future
workers. Keep them stopped until both the SQL dump and photo archive complete.
A SQL snapshot alone cannot atomically capture filesystem changes. Use a private
backup directory outside the repo and set a restrictive umask:

```sh
umask 077
mkdir -p /srv/aldia-backups/restore-point
cd /srv/aldia-backups/restore-point
# pg service configuration is provisioned privately by the operator.
pg_dump --dbname=service=aldia-backup --format=custom --file=database.dump
# PHOTO_DIR must be set to the actual persistent photo directory.
tar --create --file=photos.tar --directory="$PHOTO_DIR" .
sha256sum database.dump photos.tar > SHA256SUMS
```

Record UTC time, application revision, PostgreSQL version, Alembic revision,
report/event counts and photo-file count in a manifest, with no report payloads.
Check all commands succeeded before resuming writers. Protect the manifest and
checksums with the archive; checksums detect corruption, not malicious tampering.
SQL dumps include staff password hashes, sessions and audit records: handle them
as sensitive even when report fixtures are synthetic.

For local SQLite, stop writers and use SQLite's backup API instead of copying an
open database (which could omit WAL data). `SQLITE_SOURCE` and `SQLITE_BACKUP` are
operator-selected paths outside the repo:

```sh
python3 - <<'PY'
import os
import sqlite3
with sqlite3.connect(os.environ['SQLITE_SOURCE']) as source:
    with sqlite3.connect(os.environ['SQLITE_BACKUP']) as destination:
        source.backup(destination)
PY
```

Archive the photo directory during the same stopped-write window.

## Restore drill (isolated environment)

1. Provision an empty PostgreSQL database of a compatible version, a private empty
   photo directory and a separate API instance. Configure a separate hostname;
   keep the restored service off the public network. Do not overwrite live data.
2. Verify `sha256sum --check SHA256SUMS`. Restore a trusted dump into the empty
   database using a privately provisioned service entry:

   ```sh
   pg_restore --dbname=service=aldia-restore-test --no-owner --no-acl \
     --exit-on-error database.dump
   tar --extract --file=photos.tar --directory="$RESTORE_PHOTO_DIR" \
     --no-same-owner --no-same-permissions
   chmod 700 "$RESTORE_PHOTO_DIR"
   find "$RESTORE_PHOTO_DIR" -type f -name '*.jpg' -exec chmod 600 {} +
   ```

   Extract only your trusted archive into that empty directory; set ownership to
   the service account. For SQLite restore the backup database to a new test path
   with the same backup API and run `PRAGMA integrity_check` (must return `ok`).
3. Match the application's recorded revision. Run `uv run alembic current` and
   compare to the manifest; migrate only a disposable copy if the deployed code
   needs a newer revision. Never use demo seeding to repair production data.
4. Before serving, invalidate restored staff sessions with
   `DELETE FROM staff_sessions;` in the isolated SQL console. Restore tests must
   not revive old credentials; bootstrap a test admin privately if necessary.
5. Start a private verifier and the restored API with its restored SQL and photo
   paths. Require `/api/health` HTTP 200. Compare report/event counts to the
   manifest, load list/detail/timeline, fetch three known photos, compare file
   hashes, and inspect CSV and Open311. Check UUID photos against SQL rows in both
   directions; document missing files or orphans without deleting them blindly.
6. Make a synthetic test report and staff transition in the isolated instance;
   verify writes, event ordering and a photo surviving restart. Record date,
   elapsed restore time, counts/checksums and outcome. Destroy the test copy after
   review. Drill before a pilot and monthly thereafter; a backup is unproven
   until restored. Production cutover needs an agreed maintenance window and a
   fresh consistent recovery point.

## Data-protection note (engineering proposal)

Reports store category, problem coordinates, capture/creation/state timestamps,
metadata-stripped photo, optional citizen note, verifier checks and image hash,
workflow state, assignment, duplicate linkage and public/internal staff events.
No citizen account, phone, email, name or device identifier is stored in a report.
Do not submit personal data of citizens in photos or notes. Public readers can
see problem locations and notes; free text/photos can still contain personal
information despite the absence of identity fields. Review and moderate such
content before a real pilot; automatic blurring/redaction is not implemented.
Staff usernames/roles, Argon2 password hashes, expiring sessions and auth audits
are stored separately; public event attribution currently exposes staff usernames.
Use institutional staff identifiers and review that publication with the city.

Proposed pilot retention, subject to municipal approval and implementation:
resolved/closed report data and photos for 180 days, open cases reviewed every
90 days, auth audit for 90 days, application logs for 14 days, backups for 30 days.
Unanswered/pending reports need review within seven days. These are proposals;
automatic retention/deletion jobs and citizen self-service deletion do not exist.
Idempotency records expire after 24 hours and are purged on later creation;
staff sessions expire after 12 hours and are checked on use. Agree purpose,
access roles, deletion authority and a contact for correction/removal before using
real citizen data. Deletion must address SQL events/links and files together and
age out backups according to the approved policy.

## Recorded local recovery check (2026-11-20)

An isolated synthetic SQLite database was migrated to `0004`, seeded twice
(idempotent), backed up with SQLite's backup API, and restored alongside a photo
archive. Integrity check passed: 62 reports, 265 events, and all 62 JPEG SHA-256
hashes matched. The restored API and a real local verifier process returned
healthy readiness; three comparison photos, CSV BOM, six Open311 services and
OpenAPI response examples were checked over HTTP. The Server banner was absent
and JSON request records contained only their documented allowlist. Temporary
services/data were removed. PostgreSQL restore, container behavior and browser
walkthrough remain unverified; this check does not establish a production RTO.
