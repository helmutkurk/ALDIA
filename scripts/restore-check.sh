#!/usr/bin/env bash
# Timed restore drill for a backup made by scripts/backup.sh. Everything runs in
# throwaway containers on an internal Docker network (no published ports); live
# data is never touched and all of it is removed at the end.
#
#   scripts/restore-check.sh /srv/aldia-backups/<timestamp>   (or: make restore-check BACKUP=...)
#
# Checks: SHA256SUMS; pg_restore into an empty PostgreSQL; Alembic revision and
# row counts against the manifest; every photo hash after extraction; report rows
# against photo files in both directions; then a restored API (with sessions
# invalidated) must answer /api/health with 200 and serve three photos unchanged.
# Prints the elapsed time, the measured recovery time for this backup size.
set -euo pipefail
set +x
export LC_ALL=C  # byte-order sort, to match comm and PostgreSQL uuid order

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT=${COMPOSE_PROJECT_NAME:-aldia}
API_IMAGE=${API_IMAGE:-$PROJECT-api}
VERIFIER_IMAGE=${VERIFIER_IMAGE:-$PROJECT-verifier}
TOOL_IMAGE=postgres:17-alpine
UUID_JPG='^\./[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'

die() { echo "restore-check: FAILED: $*" >&2; exit 1; }
ok() { echo "  ok  $*"; }

[[ $# -eq 1 && -f $1/manifest.txt ]] || die "usage: $0 <backup directory with manifest.txt>"
BACKUP=$(cd -- "$1" && pwd)
for image in "$API_IMAGE" "$VERIFIER_IMAGE"; do
  docker image inspect "$image" >/dev/null 2>&1 \
    || die "image $image missing; build it first with: docker compose build"
done
manifest() { sed -n "s/^$1=//p" "$BACKUP/manifest.txt"; }

START=$(date +%s)
RUN=aldia-restore-$(openssl rand -hex 4)
PASSWORD=$(openssl rand -hex 24)  # throwaway, never printed
WORK=$(mktemp -d)
cleanup() {
  rm -rf -- "$WORK"
  docker rm -f "$RUN-api" "$RUN-verifier" "$RUN-db" >/dev/null 2>&1 || true
  docker volume rm "$RUN-photos" >/dev/null 2>&1 || true
  docker network rm "$RUN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "restore-check: $BACKUP"
(cd -- "$BACKUP" && sha256sum --quiet --check SHA256SUMS) || die "checksums do not match"
ok "SHA256SUMS"
BAD=$(tar -tf "$BACKUP/photos.tar" | grep -Evc "$UUID_JPG" || true)
[[ $BAD -eq 0 ]] || die "photos.tar contains $BAD unexpected entries"
ok "photos.tar holds only <uuid>.jpg files"

docker network create --internal "$RUN" >/dev/null
docker run -d --name "$RUN-db" --network "$RUN" \
  -e POSTGRES_USER=aldia -e POSTGRES_DB=aldia -e POSTGRES_PASSWORD="$PASSWORD" \
  "$TOOL_IMAGE" >/dev/null
for _ in $(seq 60); do
  # TCP only answers once the init phase (socket-only server) is over.
  docker exec "$RUN-db" pg_isready -h 127.0.0.1 -U aldia -d aldia -q 2>/dev/null && break
  sleep 1
done
sql() { printf '%s\n' "$1" | docker exec -i "$RUN-db" psql -U aldia -d aldia -XAtq -v ON_ERROR_STOP=1; }
sql 'SELECT 1' >/dev/null || die "restore database did not start"

docker exec -i "$RUN-db" pg_restore -U aldia -d aldia --no-owner --no-acl --exit-on-error \
  <"$BACKUP/database.dump" || die "pg_restore"
ok "pg_restore into an empty PostgreSQL $(sql 'SHOW server_version')"

[[ $(sql 'SELECT version_num FROM alembic_version') == "$(manifest alembic_revision)" ]] \
  || die "Alembic revision differs from the manifest"
for table in reports report_events; do
  [[ $(sql "SELECT count(*) FROM $table") == "$(manifest "$table")" ]] \
    || die "$table count differs from the manifest"
done
ok "Alembic $(manifest alembic_revision), $(manifest reports) reports, $(manifest report_events) events"

# Restored sessions must not revive old logins.
for table in staff_sessions citizen_sessions; do
  if [[ -n $(sql "SELECT to_regclass('public.$table')") ]]; then
    sql "DELETE FROM $table" >/dev/null
  fi
done
ok "staff and citizen sessions invalidated"

docker volume create "$RUN-photos" >/dev/null
docker run --rm -i --network none -v "$RUN-photos:/photos" -w /photos "$TOOL_IMAGE" sh -c \
  'tar -xof - && chown -R 10001:10001 . && chmod 700 . && find . -type f -exec chmod 600 {} +' \
  <"$BACKUP/photos.tar"
docker run --rm --network none --user 10001:10001 -v "$RUN-photos:/photos:ro" -w /photos \
  "$TOOL_IMAGE" sh -c "find . -maxdepth 1 -type f -name '*.jpg' | sort | xargs -r sha256sum" \
  | cmp -s - "$BACKUP/photos.sha256" || die "photo hashes differ after extraction"
ok "$(manifest photo_files) photos extracted (0700/0600, UID 10001), all hashes match"

sql 'SELECT id FROM reports ORDER BY 1' >"$WORK/ids-sql"
sed -E 's#.*\./([0-9a-f-]+)\.jpg$#\1#' "$BACKUP/photos.sha256" | sort >"$WORK/ids-photos"
MISSING=$(comm -23 "$WORK/ids-sql" "$WORK/ids-photos" | wc -l)
ORPHANS=$(comm -13 "$WORK/ids-sql" "$WORK/ids-photos" | wc -l)
[[ $MISSING -eq $(manifest reports_without_photo) && $ORPHANS -eq $(manifest photos_without_report) ]] \
  || die "report/photo cross-check differs from the manifest"
ok "rows vs. files: $MISSING reports without photo, $ORPHANS photos without report (as recorded)"

docker run -d --name "$RUN-verifier" --network "$RUN" -e VERIFIER_MODE=stub \
  "$VERIFIER_IMAGE" >/dev/null
docker run -d --name "$RUN-api" --network "$RUN" -v "$RUN-photos:/data/photos" \
  -e DATABASE_URL="postgresql+psycopg://aldia:$PASSWORD@$RUN-db:5432/aldia" \
  -e PHOTO_DIR=/data/photos -e VERIFIER_URL="http://$RUN-verifier:8001" \
  "$API_IMAGE" >/dev/null

# Three visible reports whose photos must come back byte for byte over HTTP.
SAMPLE=$(sql "SELECT id FROM reports WHERE state <> 'oculto' ORDER BY id" \
  | comm -12 - "$WORK/ids-photos" | head -3)
EXPECTED=$(for id in $SAMPLE; do grep -F "./$id.jpg" "$BACKUP/photos.sha256" | cut -d' ' -f1; done)
SERVED=$(docker exec -i "$RUN-api" python - $SAMPLE <<'PY'
import hashlib, sys, time, urllib.error, urllib.request
base = "http://127.0.0.1:8000/api"
for _ in range(60):
    try:
        with urllib.request.urlopen(f"{base}/health", timeout=3) as response:
            if response.status == 200:
                break
    except (urllib.error.URLError, OSError):
        pass
    time.sleep(1)
else:
    sys.exit("health never answered 200")
for report_id in sys.argv[1:]:
    with urllib.request.urlopen(f"{base}/reports/{report_id}/photo", timeout=5) as response:
        print(hashlib.sha256(response.read()).hexdigest())
PY
) || die "the restored API was not healthy or did not serve the sample photos"
[[ -n $SAMPLE && $SERVED == "$EXPECTED" ]] || die "the restored API served different photos"
ok "restored API: /api/health 200, $(wc -w <<<"$SAMPLE") photos served unchanged"

ELAPSED=$(($(date +%s) - START))
BYTES=$(du -cb "$BACKUP/database.dump" "$BACKUP/photos.tar" | tail -1 | cut -f1)
echo "restore-check: PASSED in ${ELAPSED}s for $((BYTES / 1024 / 1024)) MiB" \
  "(backup $(manifest created_utc), revision $(manifest app_revision | cut -c1-12))"
