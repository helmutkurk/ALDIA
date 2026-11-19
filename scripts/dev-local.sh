#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LOCAL="$ROOT/.local"
CONTROL="$LOCAL/dev.control"
cd "$ROOT"

# A held lock proves ownership even across process namespaces. No PID reuse risk.
is_running() {
  [[ -f "$LOCAL/dev.lock" ]] && ! flock -n "$LOCAL/dev.lock" true
}

status() {
  local failed=0 url name
  if is_running; then
    echo 'Local stack supervisor is running (startup lock held).'
  else
    echo 'Local stack supervisor is stopped.'
    failed=1
  fi
  for name in verifier api portal; do
    case "$name" in
      verifier) url=http://127.0.0.1:8001/health ;;
      api) url=http://127.0.0.1:8000/api/health ;;
      portal) url=http://127.0.0.1:5173/api/health ;;
    esac
    if curl --noproxy '*' --fail --silent --max-time 2 "$url" >/dev/null; then
      echo "$name: healthy ($url)"
    else
      echo "$name: unavailable ($url)"
      failed=1
    fi
  done
  return "$failed"
}

case "${1:-start}" in
  status) status; exit $? ;;
  stop)
    if ! is_running; then
      echo 'Local stack is already stopped.'
      exit 0
    fi
    # Send a command to the owner; never signal an unrelated process.
    timeout 3 bash -c 'printf "stop\n" > "$1"' _ "$CONTROL"
    for ((i=0; i<100; i++)); do
      if ! is_running; then
        echo 'Local stack stopped.'
        exit 0
      fi
      sleep 0.1
    done
    echo 'Supervisor did not stop; inspect .local/logs/.' >&2
    exit 1
    ;;
  start|--smoke) ;;
  *) echo 'Usage: scripts/dev-local.sh [start|--smoke|stop|status]' >&2; exit 2 ;;
esac

for command in uv npm node python3 curl make setsid flock timeout; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
mkdir -p "$LOCAL/logs" "$LOCAL/photos"
exec 9>"$LOCAL/dev.lock"
if ! flock -n 9; then
  echo 'A local stack already owns the startup lock.'
  if [[ "${1:-}" == --smoke ]]; then
    echo 'Stop it with make dev-stop, then restart with --smoke to inherit fresh tokens.' >&2
    exit 1
  fi
  status
  exit $?
fi

children=()
cleanup() {
  local result=$? pid alive
  trap - EXIT INT TERM
  for pid in "${children[@]}"; do kill -TERM -- "-$pid" 2>/dev/null || true; done
  for ((attempt=0; attempt<50; attempt++)); do
    alive=0
    for pid in "${children[@]}"; do
      if kill -0 -- "-$pid" 2>/dev/null; then alive=1; fi
    done
    [[ "$alive" == 1 ]] || break
    sleep 0.1
  done
  for pid in "${children[@]}"; do
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm "$CONTROL"
  echo 'Local stack stopped.'
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -e "$CONTROL" ]]; then rm "$CONTROL"; fi
mkfifo "$CONTROL"
exec 8<>"$CONTROL"

handle_control() {
  local message
  if read -r -t 0.1 message <&8 && [[ "$message" == stop ]]; then exit 0; fi
}
start() {
  local name=$1 directory=$2
  shift 2
  (cd "$directory"; exec setsid "$@") 8>&- 9>&- >"$LOCAL/logs/$name.log" 2>&1 &
  children+=("$!")
}
run_task() {
  local name=$1 pid
  start "$@"
  pid=${children[${#children[@]}-1]}
  while kill -0 "$pid" 2>/dev/null; do handle_control; done
  if ! wait "$pid"; then
    echo "$name failed; inspect .local/logs/$name.log" >&2
    return 1
  fi
  unset 'children[${#children[@]}-1]'
}

# Refuse occupied ports; never stop another application's processes.
python3 - <<'PY'
import socket

for port in (8001, 8000, 5173):
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(("127.0.0.1", port))
        except OSError:
            raise SystemExit(f"Port {port} is occupied; stop its owner and retry.") from None
PY

export UV_CACHE_DIR="$LOCAL/uv-cache" UV_NO_ENV_FILE=1
unset UV_ENV_FILE STAFF_TOKEN SUPERVISOR_TOKEN
export DATABASE_URL="sqlite:///$LOCAL/aldia.db" PHOTO_DIR="$LOCAL/photos"
export VERIFIER_URL=http://127.0.0.1:8001 VERIFIER_MODE=stub MAX_AGE_SECONDS=600
export CORS_ORIGINS=http://localhost:5173,http://127.0.0.1:5173
export VITE_API_BASE_URL=/api

echo 'Preparing existing pinned dependencies (logs: .local/logs/setup.log)...'
run_task setup "$ROOT" bash -c '
  set -euo pipefail
  uv sync --frozen --project backend/verifier
  uv sync --frozen --project backend/api
  cd portal
  if [[ ! -d node_modules ]]; then npm ci; fi
'

# Shell variables only; credentials are passed to API/smoke child environments.
staff_token=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
supervisor_token=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
echo 'STAFF_TOKEN and SUPERVISOR_TOKEN set (values are never printed or saved).'

wait_health() {
  local name=$1 url=$2 pid=${children[${#children[@]}-1]}
  for ((attempt=0; attempt<120; attempt++)); do
    handle_control
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$name exited; inspect .local/logs/$name.log" >&2
      return 1
    fi
    if curl --noproxy '*' --fail --silent --max-time 1 "$url" >/dev/null; then
      echo "$name: healthy"
      return 0
    fi
    sleep 0.25
  done
  echo "$name health timed out; inspect .local/logs/$name.log" >&2
  return 1
}

start verifier "$ROOT/backend/verifier" uv run --frozen --no-env-file uvicorn \
  app.main:create_app --factory --host 127.0.0.1 --port 8001 --no-access-log
wait_health verifier http://127.0.0.1:8001/health
run_task migrate "$ROOT/backend/api" uv run --frozen --no-env-file alembic upgrade head
STAFF_TOKEN="$staff_token" SUPERVISOR_TOKEN="$supervisor_token" \
  start api "$ROOT/backend/api" uv run --frozen --no-env-file uvicorn \
    app.main:create_app --factory --host 127.0.0.1 --port 8000 --no-access-log
wait_health api http://127.0.0.1:8000/api/health
start portal "$ROOT/portal" npm run dev -- --host 127.0.0.1 --port 5173 --strictPort --mode local-stack
wait_health portal http://127.0.0.1:5173/
# This also proves that the portal can reach the API through its dev proxy.
wait_health portal http://127.0.0.1:5173/api/health
run_task seed "$ROOT" make seed
echo 'Demo seed ready (details: .local/logs/seed.log).'
printf '\nPortal:   http://localhost:5173\nAPI:      http://localhost:8000/api/health\nAPI docs: http://localhost:8000/docs\nVerifier: http://localhost:8001/health\nLogs:     .local/logs/\n'
if [[ "${1:-}" == --smoke ]]; then
  STAFF_TOKEN="$staff_token" SUPERVISOR_TOKEN="$supervisor_token" \
    run_task smoke "$ROOT" bash scripts/smoke-local.sh
  cat "$LOCAL/logs/smoke.log"
fi
echo 'Ready. Ctrl-C or make dev-stop stops all services.'
# Watch both the command pipe and services; a failed service stops the whole stack.
while true; do
  handle_control
  for pid in "${children[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo 'A service exited; stopping the local stack. Inspect .local/logs/.' >&2
      exit 1
    fi
  done
done
