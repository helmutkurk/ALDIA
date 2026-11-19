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

## 2026-11-19 21:50 CET - contract v0.3 dashboard harvest
- Worked directly on `develop` as requested. No commits, branch changes, merges, pushes or remote deletion;
  commit hash: not applicable. Concurrent app work and its documentation were left untouched. No dependencies,
  lockfiles, environment-file contents, credentials or personal photos were used.
- Source: Isabel Sagastume's `origin/dashboard`, local reference
  `98eedcae641d24408084e9c86d55649037ae9391`, plus the existing harvest analysis. Read her statistics logic,
  chart/table presentation and synthetic demo generator with `git show`; no checkout, execution or wholesale copy.
  `git fetch origin` was attempted but the sandbox rejected writing `.git/FETCH_HEAD` (read-only filesystem).
  Remote freshness is therefore unverified; the branch remains intact.
- Wrote the v0.3 section in `documentation/api-contract.md` before implementation. Added `por_categoria`
  and `top_categorias` to `GET /api/stats`, with explicit state buckets, nullable duration samples, median,
  interpolated p90 and deterministic top-five tie ordering. All new metrics use the filtered creation cohort;
  existing v0.2 resolution-period KPIs retain their formulas. Pending verification counts as category-open;
  verifier rejection counts as category-closed. The contract and Spanish chart notes explain the distinction.
- Ported ideas: category repair-time bars (median, p90, sample count), frequency bars split resolved/open/closed,
  KPI strip, hover/focus tooltips, and equivalent tables under native keyboard-operable **Ver tabla** disclosures.
  Reimplemented with our category ids, state names, DOM helpers, Spanish `i18n.js`, existing style tokens and Vitest.
  SVG bars have focus targets, text descriptions, Escape-dismissable tooltips and visible numeric labels;
  tables have captions, scoped headers and keyboard-focusable horizontal scrolling on narrow screens.
  v0.3 initial rendering uses one stats request. The existing detailed category/state-group table is preserved
  behind a disclosure and loads its joint-distribution queries on demand; v0.2 fallback remains supported.
- Expanded our existing server seed from 44 to 62 reports (26 resolved), adding three explicit repair-hour samples
  per category. New ids append after the original 44; existing rows are skipped, so repeated seeding remains
  idempotent. All new samples fit the default 30-day window. Notes retain `[demo]`; photos are generated shapes.
- Dropped/deferred: `por_municipio_zona` and the zone table (no report zone/municipality field; demo-note text is
  not structured geography); severity-based SLA and repair-photo confirmation rules (not in our state model);
  client-side filtering/statistics/clustering/exports (API remains authoritative); her alternate endpoints,
  shell, build/test setup, styles, logos, assets and mock/API switch (ours already cover these; no parallel contract
  or vendored material). Extra map pulse/toast/before-after features are outside this harvest's scope.
- Verification: new API and portal tests first failed on the missing v0.3 fields/charts, then passed. Hand-computed
  assertions cover even/odd/singleton medians, interpolated p90, zero-hour samples, missing timestamps, reopened
  and hidden cases, filters/local-day boundaries, six-category top-five ranking and empty results. Seed tests
  verify exact samples, default-window coverage, ordered events and repeated seeding. Portal tests exercise real
  DOM focus, Escape, pointer tooltips, table disclosures, null-versus-zero presentation, labels and lazy detail loading.
- Checks: `make -C backend/api lint test` passed Ruff, formatting, strict mypy and **360 tests** (one existing
  Starlette/httpx deprecation warning); `cd portal && npm run check` passed ESLint, Prettier, **112 tests** and
  production build. UV needed `UV_CACHE_DIR=/tmp/aldia-uv-cache` because the default cache is read-only.
  No Vite-loadable environment files were present (existence check only). `git diff --check` passed.
- Browser limitation: connected browser inventory returned `The browser access host is unavailable`; no browser
  was launched in the sandbox. Desktop/mobile rendering and actual keyboard/hover behavior in a real browser
  remain for Claude/Helmut: run `make dev-all` outside this job and inspect `http://localhost:5173/#/panel`, both
  chart tables and tooltips at desktop and phone widths. Vault/session maintenance is handed to the orchestrator
  because this job authorizes writes only in `backend/api`, `portal` and `documentation`.
