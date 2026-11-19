# Log: omarchy (main laptop)

Append-only, one block per iteration. Plan: `documentation/mvp-plan.md`.

## 2026-11-19 20:3x - loop started
- Router: Claude 5 h window 88 % used (resets 23:20), Codex 95 % (resets 23:51): both blocked.
- Action: no work; first working iteration scheduled right after 23:20.
- Next: backlog item 1 (`scripts/dev-local.sh`, `make dev-all`).

## 2026-11-19 21:03 CET - one-command local stack and real-request smoke
- Work stayed on `develop`; no commits, branch switches, pushes or Docker. No dependencies were added. Concurrent
  `app/` work was left untouched. Commit hash: not applicable; the orchestrator owns commits.
- Added `scripts/dev-local.sh`, `make dev-all`, `make dev-status` and `make dev-stop`. Startup prepares existing pinned
  dependencies, starts the stub verifier on 8001, migrates `.local/aldia.db` with Alembic before starting the API on
  8000, starts Vite on 5173, checks health (including its API proxy), and runs `make seed`. Data/photos/logs and the
  control pipe/lock stay under ignored `.local/`. Tokens are random, passed only to API/smoke child environments,
  and never printed or saved. Vite's `local-stack` mode disables environment-file loading.
- Added reusable `scripts/smoke-local.sh` / `scripts/smoke_local.py`; `make dev-all SMOKE=1` inherits credentials
  without exposing them. Final run passed **21 real curl requests**: three health checks, portal HTML, six categories,
  list, a fresh Pillow 1280x960 JPEG with source EXIF GPS, create `201`, identical idempotency replay `200` and exactly
  one new report, stored JPEG without EXIF/GPS, both nearby routes, clusters, stats, semicolon CSV with UTF-8 BOM,
  staff transition without token `401`, illegal transition `409`, legal transition `200`, and its public timeline event.
  Result: `.local/logs/smoke.log`; temporary images/responses are removed. Each smoke run keeps one synthetic report.
- Failures found and fixed: the first smoke assertion incorrectly equated `recibidos` with total reports; pending
  verification is excluded by the existing stats implementation/tests, so the assertion now accounts for it. The
  initial PID-based supervisor check failed across this sandbox's per-command PID namespaces; replaced it with a
  held lock and command pipe. No backend endpoint defect was exposed by the completed smoke run.
- Lifecycle verified: a second `make dev-all` reused the healthy stack; restarts logged `Created 0, already present 44`
  for the seed. `make dev-status` succeeded while running. A real SIGINT test observed the cleanup trap and all three
  ports closed. `make dev-stop` succeeded from another command/namespace; repeating it succeeded as already stopped.
  An occupied-port test rejected startup, preserved the existing listener, and started no services. Final stack is stopped.
- Checks: `make -C backend/api lint test` passed Ruff, formatting, strict mypy and **358 tests** (one existing
  Starlette/httpx deprecation warning). `cd portal && npm run check` passed lint/format, **110 tests** and production
  build. `bash -n` passed for both shell scripts; the smoke helper passed Ruff check/format; `git diff --check` passed.
  Only API/portal checks were run; no verifier or app suite was run.
- Browser not verified: connected browser inventory returned `browser access host is unavailable`; Playwright is
  absent from the repo, and the sandbox hook prohibits browser launches. The hook also rejected a syntax-only Node
  check of the capture script; it was not executed. Prepared `scripts/screenshot-local.mjs` for Helmut/Claude to run
  outside the sandbox with an existing Playwright installation: `node scripts/screenshot-local.mjs`. It waits for
  map/markers and a list item before saving `.local/shots/portal.png`. No screenshot was produced; map rendering,
  tiles, browser interactions and mobile layout remain unverified. The verifier remains an explicitly labelled stub.
- Updated README Quick start, `documentation/dev-setup.md` and the managed-start pointer in `documentation/testing.md`.
  Next: browser acceptance/capture outside the sandbox, then the remaining app/device acceptance work from the MVP plan.

## 2026-11-19 21:1x - decisions
- Helmut approved porting Isabel's useful pieces (stats logic, chart tooltips with table alternative, demo data) and deleting `dashboard` afterwards.
- Android/iOS: prepare everything that is independent of accounts; the rest is created by Helmut later (job 9).
- Codex jobs 1 (dev-local) and 2 (app UI parity) running; Claude 5 h window resets 23:20, Codex 01:51.
- Final quality pass with the Cursor skill `hks-thermo-nuclear-code-quality-review` (job 10); Notion hand-off and release at the end (jobs 11-12).
