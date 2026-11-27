#!/usr/bin/env bash
# Consistent backup of the Docker stack: SQL dump and photo volume from one
# stopped-write window, plus checksums and a manifest without report payloads.
#
#   scripts/backup.sh /srv/aldia-backups        (or: make backup BACKUP_DIR=...)
#
# Creates <dir>/<UTC timestamp>/ with database.dump, photos.tar, photos.sha256,
# manifest.txt and SHA256SUMS. The API is stopped while the copy runs and started
# again afterwards. Thumbnails are a cache and are left out (regenerated on use).
# Check a backup with scripts/restore-check.sh. See documentation/operations.md.
set -euo pipefail
set +x
export LC_ALL=C  # byte-order sort, to match comm and PostgreSQL uuid order

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT=${COMPOSE_PROJECT_NAME:-aldia}
TOOL_IMAGE=postgres:17-alpine
COMPOSE=(docker compose --project-directory "$ROOT" --project-name "$PROJECT")

die() { echo "backup: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "usage: $0 <backup directory outside the repo>"
BASE=$(realpath -m -- "$1")
case "$BASE/" in "$ROOT"/*) die "the backup directory must be outside the repo" ;; esac
umask 077
mkdir -p -- "$BASE"

VOLUME=$(docker volume ls -q \
  --filter "label=com.docker.compose.project=$PROJECT" \
  --filter "label=com.docker.compose.volume=photos")
[[ -n $VOLUME ]] || die "no photos volume for compose project '$PROJECT'"
"${COMPOSE[@]}" ps --status running --services | grep -qx db || die "the db service is not running"

DEST="$BASE/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -- "$DEST" || die "$DEST already exists"

sql() {  # run one query in the db service, print bare tuples
  printf '%s\n' "$1" | "${COMPOSE[@]}" exec -T db \
    sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -XAtq -v ON_ERROR_STOP=1'
}

in_volume() {  # read-only shell in the photo volume as the API user, no network
  docker run --rm --network none --user 10001:10001 \
    -v "$VOLUME:/photos:ro" -w /photos "$TOOL_IMAGE" sh -c "$1"
}

# Stop every writer for the whole window; start the API again on any exit.
API_WAS_RUNNING=0
if "${COMPOSE[@]}" ps --status running --services | grep -qx api; then
  API_WAS_RUNNING=1
fi
restart_api() {
  if [[ $API_WAS_RUNNING -eq 1 ]]; then "${COMPOSE[@]}" start api >/dev/null 2>&1; fi
}
trap restart_api EXIT
"${COMPOSE[@]}" stop api >/dev/null 2>&1 || true

cd -- "$DEST"
"${COMPOSE[@]}" exec -T db \
  sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' >database.dump
in_volume "find . -maxdepth 1 -type f -name '*.jpg' ! -name '*.thumb.jpg' | sort | tar -cf - -T -" \
  >photos.tar
in_volume "find . -maxdepth 1 -type f -name '*.jpg' ! -name '*.thumb.jpg' | sort | xargs -r sha256sum" \
  >photos.sha256

# Cross-check report rows against photo files (counts only, nothing is deleted).
sql "SELECT id FROM reports ORDER BY 1" >"$DEST/.ids-sql"
sed -E 's#.*\./([0-9a-f-]+)\.jpg$#\1#' photos.sha256 | sort >"$DEST/.ids-photos"
MISSING=$(comm -23 .ids-sql .ids-photos | wc -l)
ORPHANS=$(comm -13 .ids-sql .ids-photos | wc -l)
rm -f .ids-sql .ids-photos

{
  echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "app_revision=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "postgres_version=$(sql 'SHOW server_version')"
  echo "alembic_revision=$(sql 'SELECT version_num FROM alembic_version')"
  echo "reports=$(sql 'SELECT count(*) FROM reports')"
  echo "report_events=$(sql 'SELECT count(*) FROM report_events')"
  echo "photo_files=$(wc -l <photos.sha256)"
  echo "reports_without_photo=$MISSING"
  echo "photos_without_report=$ORPHANS"
} >manifest.txt

sha256sum database.dump photos.tar photos.sha256 manifest.txt >SHA256SUMS
restart_api
trap - EXIT

cat manifest.txt
echo "backup: written to $DEST"
if [[ $MISSING -ne 0 || $ORPHANS -ne 0 ]]; then
  echo "backup: warning: $MISSING reports without photo, $ORPHANS photos without report" >&2
fi
