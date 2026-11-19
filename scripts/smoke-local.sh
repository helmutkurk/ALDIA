#!/usr/bin/env bash
set -euo pipefail
set +x
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Run via dev-local.sh --smoke to inherit the generated API credentials.
exec uv run --project "$ROOT/backend/api" --frozen --no-env-file \
  python "$ROOT/scripts/smoke_local.py"
