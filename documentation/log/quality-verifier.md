# Verifier quality audit

Review date: 2026-11-20. Scope: all of `backend/verifier`, treated as a
pull request against the maintainability standards in the supplied Cursor review
prompt. References below identify the pre-refactor source lines.

## Ranked findings and restructuring plan

1. **P2 — Unchecked EXIF values cross the image boundary.**
   `backend/verifier/app/imaging.py:23`, `:28`,
   `backend/verifier/app/checks/exif_gps.py:9`, and
   `backend/verifier/app/checks/exif_time.py:18` propagate `Any` dictionaries and
   parse raw Pillow values inside policy checks. Strict mypy cannot check these
   operations. **Plan:** normalize EXIF once while the image is open, into frozen
   capture-time and coordinate models with explicit missing/invalid states. Keep
   raw unknown values confined to the metadata parser, reuse its exception
   policy, and let checks only evaluate age, consistency and distance. Preserve
   missing versus malformed semantics, offsets, limits, codes and detail strings.

2. **P2 — Shared decoding stops short of shared grayscale preparation.**
   `backend/verifier/app/checks/registry.py:46`,
   `backend/verifier/app/checks/screen_photo.py:39`, and
   `backend/verifier/app/phash.py:6` each convert the full RGB image to grayscale.
   Decoding is already shared; it must stay that way.
   **Plan:** prepare one full-resolution grayscale source per verification and
   derive each existing resize independently. Keep `dhash(image)` compatible
   with RGB and grayscale callers. Never derive the screen image or hash from
   the 320-pixel thumbnail: repeated resizing would change measured results.

3. **P2 — The service README describes a superseded implementation.**
   `backend/verifier/README.md:15`, `:32`, `:42`, `:51`, and `:66` describe stub
   response mode, omit heuristic checks/configuration and point to the removed
   `app/checks.py` monolith. **Plan:** document the current modules, heuristic
   defaults, limitations and classifier protocol (including required `code`),
   referencing the existing binding contract without editing that contract.

4. **P3 — HTTP error classification catches all verifier ValueErrors.**
   `backend/verifier/app/main.py:90` maps any pipeline `ValueError` to 422,
   including a potential classifier/programming failure. **Planned restructuring
   deferred:** dedicated image-input exceptions could narrow this boundary, but
   would change currently observable failure behavior. Preserve the existing
   statuses and generic coordinate-free log message in this behavior-preserving
   task. A separate change should define and test the intended failure contract.

## Whole-area assessment

- Existing `HARD_CHECKS`, `CheckContext`, Pydantic `Check`/`VerifyResult`, and
  `Classifier` protocol already separate orchestration, policy and HTTP concerns.
  Keep them; a plugin framework or per-check wrappers would add indirection.
- All 19 application modules are below 300 lines (largest: `main.py`, 101).
  Both existing test modules are below 300 lines. No file approaches 1,000 lines.
- Exposure/time decision precedence is short and meaningful; replacing it with
  tables or a state machine would obscure policy. Keep the algorithms/thresholds.
- Verification computes request-local results before returning. There is no
  persistence or related multi-write state requiring an atomic update.
- Checks are synchronous CPU/Pillow work already offloaded from the event loop
  as one request job. There is no independent async I/O being serialized.
  Per-check threads would add scheduling/shared-image complexity without evidence
  of an improvement; retain deterministic check/classifier execution order.
- HTTP errors already have generic envelopes; unexpected failures log no input,
  coordinates, filenames, exception text or image contents. Preserve that policy.
- Docker, upload middleware, settings validation, hash bit order, classifier stub,
  training placeholder, public exports and dependency pins need no restructuring.

## Verification plan

Baseline: `UV_CACHE_DIR=/tmp/ciudadcheck-verifier-uv make -C backend/verifier lint test`.
The default uv cache is read-only in this sandbox; redirecting its cache changes
no project configuration or dependencies. Baseline collects 55 tests.

Add focused regressions for EXIF normalization/malformed states and shared image
preparation, including exact output equivalence, orientation, independent resize
   paths and the public RGB hash helper. Run the same required lint/test command
(ruff, formatting, strict mypy and pytest), then inspect the scoped diff. No API,
contract, dependency, lockfile, git branch, commit or push changes are authorized.

## Implementation outcome

- **Finding 1 addressed:** `app/metadata.py` owns nested-IFD resolution, time
  parsing, numeric narrowing and GPS normalization. Frozen `CaptureTime` and
  `Coordinates` models plus `ExifState.MISSING`/`INVALID` replace `Any` across
  this boundary. EXIF checks now only evaluate policy and construct the same
  results; malformed input uses the original shared exception policy.
- **Finding 2 deferred after checking callback behavior:** the public
  `Classifier.classify` callback receives the mutable decoded image after hard
  checks and before hash/screen evaluation. Caching grayscale before that
  callback changes results if the callback mutates the image. A one-conversion
  prototype was removed rather than impose a new classifier immutability
  contract or add cache invalidation/conditional plumbing. The existing one-time
  image decode and separate independent grayscale resize paths remain intact.
- **Finding 3 addressed:** README now matches heuristic health/configuration,
  check names/limitations, module locations and the required classifier result
  fields. Model integration instructions include the registry startup guard.
- **Finding 4 deferred:** preserve HTTP error classification and coordinate-free
  logging. No error status, response schema, classifier protocol, check order,
  thresholds, algorithms, image orientation or hash format was changed.
- Added 18 focused EXIF regression cases for normalized values, numeric types,
  missing versus malformed metadata, offsets, unreadable nested IFDs and model
  lifetime after the source image closes. Existing tests remain unchanged.

## Final verification

- `UV_CACHE_DIR=/tmp/ciudadcheck-verifier-uv make -C backend/verifier lint test`:
  **PASS** — ruff check, ruff formatting, strict mypy (20 application modules),
  and **73 tests** (55 existing plus 18 new). The existing Starlette/httpx
  deprecation warning remains; no dependency change was needed.
- Compared **43 complete verdicts** against the original application source
  copied from git to `/tmp`: **zero differences**. Synthetic cases covered
  JPEG/PNG, dimensions, all eight EXIF orientations, RGB/L/RGBA input, valid and
  malformed times/GPS, exposure, blur, stripes and a mutating classifier. This
  supplementary comparison script stays outside the repository.
- `git diff --check -- backend/verifier documentation/log/quality-verifier.md`:
  **PASS**. Reviewed the final changes and new files; application source has no
  explicit `Any`, casts or type-ignore suppressions.
- No dependencies, lockfiles, API files or binding contract edits were made by
  this task. No commit, branch switch or push was performed; work stays on
  `develop`. Other jobs' working-tree changes were left alone.
- All application modules remain below 300 lines; the new metadata module is
  124 lines, and the largest test is 268.
