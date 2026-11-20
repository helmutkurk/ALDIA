# Portal quality audit

Reviewed 2026-11-20 against the Thermo-Nuclear Code Quality Review prompt.
Scope: the complete `portal/` source, tests, styles, build/deployment configuration
and portal documentation, treated as a proposed pull request. References below
identify the pre-refactor checkout. This audit was written before code changes.

## Ranked findings and restructuring plan

1. **Medium — HTTP policy and endpoint definitions share one large boundary.**
   `portal/src/api.js:39`, `portal/src/api.js:92`, `portal/src/api.js:194`:
   the 357-line client interleaves deadlines, authentication expiry, response
   decoding and endpoint validation. `request` documents only cancellation even
   though it accepts methods, bodies and three response modes. Extract the real
   transport into `api-request.js`, keep `ApiError` re-exported by `api.js`, and
   name the endpoint payload validators. Preserve HTTP policy and error precedence.

2. **Medium — Boundary models are incomplete or unresolved.**
   `portal/src/api.js:6`, `portal/src/api.js:30`,
   `portal/src/api.js:321`, `portal/src/api-validation.js:18`,
   `portal/src/api-validation.js:96`: `Stats`/`Report` references cross files
   without imports; report events omit actor, queue reports omit age, and
   request options use uninformative `object` annotations. Introduce explicit
   shared JSDoc models for reports, events, stats, clusters and requests; retain
   existing public typedef paths through aliases. Do not tighten runtime
   acceptance of legacy/additive payloads during a behavior-preserving refactor.
   Also repair the omitted pagination field in `portal/src/state.js:7` and
   triage route in `portal/src/router.js:3`, and reuse the query model for filters.

3. **Medium — Workspace composition owns a nested data-loading pipeline.**
   `portal/src/main.js:75`, `portal/src/main.js:117`,
   `portal/src/main.js:136`: request scheduling encloses list pagination,
   cluster failure isolation, caching and a six-worker hydration loop. Extract
   workspace loading from DOM/route composition, flatten the cluster failure
   path, and retain parallel list/cluster requests, bounded hydration,
   page correction and stale-generation guards. Keep store updates atomic.

4. **Medium — CSV export lifecycle is embedded in dashboard rendering.**
   `portal/src/dashboard.js:27`, `portal/src/dashboard.js:96`:
   delimiter state, authenticated download, cancellation, temporary anchors and
   object-URL cleanup obscure the statistics renderer (334 lines). Move these
   responsibilities into a CSV export component whose lifetime matches the
   dashboard; retain delimiter selection across retries and revoke URLs at the
   same lifecycle points.

5. **Low — Charts duplicate canonical rendering/label helpers.**
   `portal/src/category-charts.js:8`, `portal/src/category-charts.js:13`,
   `portal/src/category-charts.js:17`, `portal/src/dashboard-trends.js:6`:
   category lookup duplicates `categoryLabel`; SVG attribute creation and number
   formatting are also repeated. Reuse the category and number helpers and give
   the two chart modules one DOM-owned SVG attribute constructor. Preserve SVG
   attributes, Spanish output, table values and accessibility behavior.

6. **Low — Independent cluster details are fetched sequentially.**
   `portal/src/selected-report.js:80`: up to five identified reports wait for
   each preceding network read. Start those reads together with rejection
   handlers attached immediately, then consume results in server order. Keep
   progressive rendering, the successful prefix before the first failure, one
   error message, shared cancellation and suppression of late responses.

## Constraints and deliberate exclusions

- No source module exceeds 1,000 lines; the largest is `main.js` (386). Aim for
  modules below 300 lines without splitting cohesive dictionaries, styles,
  Leaflet ownership or filter-control rendering merely to satisfy a line count.
- `portal/` is JavaScript, not Python: there is no portal Makefile, Ruff or
  mypy configuration. Add `make lint test` targets using the existing ESLint,
  Prettier and Vitest dependencies. Ruff/mypy strict are inapplicable; JSDoc
  models and runtime guards do not constitute a TypeScript strict migration.
- No image checks or image decoder pipeline exist here. `photo.js` already
  centralizes authenticated image loading, fallback and object-URL cleanup.
  Keep it intact; do not touch the verifier or backend.
- Keep API methods/signatures, URL filters, validation acceptance, staff rules,
  Spanish copy, CSS and `documentation/api-contract.md` unchanged. In particular,
  leave permissive assignment responses and optional v0.3 validation alone:
  tightening these would change accepted responses.
- Existing immutable store patches, six-wide singleton hydration, parallel
  category requests, deferred cross-tabs and page-by-page adjacent navigation
  already have clear ownership or data dependencies; preserve them.
- Do not introduce logging: the portal currently emits no application logs.
  Adding raw errors or report payloads could disclose coordinates or identity.
- Existing CSV progress copy references the absent `t.dash.csvLoading` key.
  Preserve that behavior here; adding user-visible copy is a separate correction.
- No dependencies, lockfile edits, commits, branch changes or pushes. Other
  concurrent work areas are outside this audit's write scope.

## Baseline and verification plan

- Baseline: ESLint and Prettier passed; 20 Vitest files / 166 tests passed.
- Initial `make -C portal lint test` failed because no Makefile exists.
- A baseline build invocation forwarded `--mode` incorrectly through npm's
  compound `check` script; this is a command error, not a source finding.
  Run Vite directly through its existing npm build script with proper `--`.
- Use Vite's existing `local-stack` mode for tests/build so configuration does
  not load environment files. Add focused behavioral tests for extracted
  request policy, workspace loading, CSV lifecycle and concurrent cluster reads.
- Completion requires `make -C portal lint test`, a production build, whitespace
  validation, and a scoped diff review. Record actual results below after edits.

## Applied restructuring and verification

All six structural findings were addressed, with the behavior limits above.

- Extracted HTTP policy into `api-request.js` (136 lines); `api.js` now owns
  endpoint construction and delegates payload checks to `api-validation.js`.
  Existing exports, error class identity, authentication expiry, CSRF,
  cancellation and deadlines remain intact.
- Added `api-types.js` (89 lines) with explicit wire and request models, repaired
  public/local type aliases, and documented endpoint result types. These are
  JSDoc declarations with runtime guards, not a new static type-checking system.
- Extracted `workspace-load.js` (113 lines). `main.js` fell from 386 to 308 lines;
  route composition stays together rather than acquiring another forwarding
  layer solely to remove eight lines. List/cluster reads still start together;
  hydration still uses at most six workers and reuses list data.
- Extracted `csv-export.js` (75 lines). `dashboard.js` fell from 334 to 274 lines;
  delimiter and object-URL state survive reloads until the same cleanup points.
- Removed duplicate SVG constructors/category lookups/number formatters. Chart
  DOM, text, accessibility and tables retain their existing test coverage.
- Cluster-selection reads start concurrently, immediately observe failures and
  render in requested order. Successful prefixes, cancellation and first-error
  presentation are preserved, including synchronous client failures.

Verification on 2026-11-20:

- `make -C portal lint test`: ESLint zero warnings; Prettier passed;
  **23 test files / 181 tests passed**, including all 166 original tests and
  15 tests limited to restructured behavior.
- `npm run build -- --mode local-stack` from `portal/`: production bundle built.
- `git diff --check -- portal documentation/log/quality-portal.md`: passed.
- Scoped diff review: API contract, CSS, package manifests and lockfile unchanged;
  no dependency additions, application logging, branch changes, commits or pushes.
- The new tests exercise pre-cancellation, timeout during decoding, malformed
  responses, list/queue uniqueness differences, list/cluster independence,
  six-wide hydration and caching, obsolete generations, page correction,
  ordered progressive cluster rendering, partial failures, CSV retries,
  delimiter persistence, duplicate-click prevention and URL cleanup.
- No browser, real-photo, live API or Docker integration run was performed.
  Existing jsdom tests verify the preserved rendering behavior.
