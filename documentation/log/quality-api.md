# API quality audit — 2026-11-20

Scope: all of `backend/api` on `develop`, reviewed as a pull request against the
Cursor thermo-nuclear quality prompt. References below name the pre-refactor
lines. Public HTTP behavior and `documentation/api-contract.md` are binding.
No dependencies, migrations, credentials, environment files, or other work areas
are to be changed.

## Ranked findings and planned restructuring

1. **Medium — report creation mixes HTTP routing, verification and persistence.**
   `backend/api/app/routes/reports.py:43-160` owns the complete creation
   transaction inside a 368-line routing module. Nested conditionals separately
   derive status and state from the same verification outcome. Move creation and
   replay ownership policy into a cohesive report-creation service; derive the
   typed initial status/state pair once. Preserve lock scope, advisory lock,
   verification/duplicate ordering, event timestamps, idempotency ownership and
   expiry, photo cleanup on commit failure, and the HTTP adapter's replay logic.

2. **Medium — OpenAPI presentation is a mutable, untyped monolith.**
   `backend/api/app/openapi.py:14,123,399,513-762` combines fixture data, operation
   descriptions, field descriptions and schema mutation in 762 lines. `Any`
   permits invalid nested accesses throughout. Separate fixture values,
   operation metadata and field metadata from installation. Describe the portion
   of FastAPI's schema actually consumed with explicit structural types at the
   framework boundary. Keep all emitted OpenAPI content identical; do not invent
   generic tree-navigation wrappers or silently tolerate malformed schemas.

3. **Medium — staff response boundaries erase their known shapes.**
   `backend/api/app/routes/auth.py:59-71,175,179-183,217-306` uses
   `dict[str, object]` for the known user/session/list shapes and a pass-through
   helper for one response-header assignment. Introduce explicit response shapes,
   retain the canonical user field allowlist, and inline the header assignment.
   Preserve existing wire values, OpenAPI response schemas, cookies, lockouts,
   CSRF checks, role authorization and audit/session transaction boundaries.

4. **Medium, deferred — demo SQL/photo operations are not one atomic unit.**
   `backend/api/scripts/seed_demo.py:575-624` commits purge rows before deleting
   files and writes seed photos before the final SQL commit. A failure can leave
   orphaned or stale files. This cannot become truly atomic through a local code
   shuffle: SQL and the filesystem need an explicit recovery/staging policy.
   Plan a separate behavior change with failure/retry semantics and fault tests;
   leave the demo workflow unchanged in this behavior-preserving review.


5. **Low — atomic photo writes have two implementations.**
   `backend/api/app/services/storage.py:47-60,91-108` duplicates temporary-file
   creation, flush/fsync, replace and unconditional cleanup for thumbnails and
   full images. Use one storage-owned atomic-write implementation. Retain private
   directory creation for original saves and the current thumbnail/cache/error
   behavior. Test replace failure, retained old content and temporary cleanup for
   both callers; do not combine the distinct image decode policies.

## Area-wide assessment and limits

Reviewed runtime modules, routes, services, bootstrap CLI, demo seeder, migration
setup/history, test coverage and project commands. No source file exceeds 1,000
lines; the largest are report tests (854), OpenAPI (762), and the seeder (734).
Aim for focused runtime modules below 300 lines. The schema catalog (414 lines)
and test/fixture catalogs do not justify arbitrary splitting solely for length.
Existing state-transition registry, filter/pagination helpers, verifier result
validation, privacy-safe logging and related SQL updates already have canonical
homes. Keep them. Image quality checks execute in the separately owned verifier:
there is no per-check image decoding loop to restructure inside this API.

Readiness probes are independent but currently serialized
(`backend/api/app/routes/health.py:12-30`). Thread orchestration would add more
machinery to this small synchronous route; defer until latency justifies it.
Creation verification and duplicate detection remain serialized deliberately:
releasing their lock can admit concurrent duplicates/idempotency conflicts.
Historical migrations and synthetic illustration code retain their semantics.

## Verification plan

- Establish the existing `make -C backend/api lint test` baseline.
- Snapshot the generated OpenAPI before editing and compare the complete result
  afterwards, including response schemas and operation identifiers.
- Add regression tests only for restructured behavior (storage failures,
  creation outcomes and OpenAPI installation/cache isolation as needed).
- Run `make -C backend/api lint test` (ruff, formatting, strict mypy, pytest).
- Review the scoped diff and verify the API contract file is unchanged.

Initial default-cache invocation failed because `/home/hks/.cache/uv` is outside
the writable sandbox. Use `UV_CACHE_DIR=/tmp/aldia-api-uv-cache` for the same Make
targets; this changes only the tool cache location.

## Applied changes

Four findings addressed; the demo cross-store recovery finding is deferred.

- Creation now lives in `app/services/report_creation.py`; the route delegates
  directly to it. Initial status/state are selected together once with explicit
  `Status`/`State` types. Route module: 368 → 249 lines; creation service: 127.
- OpenAPI now separates installation (271 lines), examples (112), operation
  metadata (282), field metadata (116), and the structural schema types (67).
  All application-owned `Any` annotations are gone. Casts occur at the
  FastAPI/Pydantic schema boundary; opaque example/schema payloads are copied,
  not navigated through untyped helper abstractions. Spanish presentation text
  is retained verbatim, including existing date-window wording.
- Staff request/response shapes live in `app/auth_schemas.py`; response
  `TypedDict`s allow static checking while explicit route response models retain
  the previous generated schemas. The shared role type lives in `security.py`
  and is reused by dependencies and input models. The user serialization
  allowlist remains canonical. Removed the single-assignment header wrapper.
  Auth route module: 306 → 286 lines.
- Full-image and thumbnail writes share `PhotoStorage._write_atomic`, including
  fsync, replacement and temporary cleanup. Thumbnail names validate the UUID
  once. Decode and encoding policies are unchanged.
- Added 11 regression cases: initial creation outcomes/events, duplicate result,
  owner-bound idempotent retries without reprocessing, fsync/replace failures for
  both image paths, successful replacement/cache reuse, and OpenAPI installation
  caching, per-app upload limits and operation-example isolation.

All changed/new runtime modules are below 300 lines. No migrations, lockfiles,
requirements, API contract, application configuration, logging behavior or
neighboring work areas were changed.

## Verification results

The initial lint baseline passed (ruff, formatting and strict mypy). The original
HTTP test run hung before its first test: `TestClient` waited for a cross-thread
asyncio callback. A bounded diagnostic run reproduced this, and an isolated
`socket.socketpair().send()` probe returned `PermissionError` / errno 1 in the
sandbox. The baseline test run was stopped; it did not report a test failure.

For verification inside this sandbox only, a temporary `sitecustomize.py` in
`/tmp/aldia-api-test-polling` subclasses the default selector and caps waits at
10 ms. This lets the event loop observe callbacks queued by other threads while
socket wakeup writes remain denied. It changes no application/test files or
permissions, installs nothing and is not part of the repository. The tool cache
also uses the writable `/tmp/aldia-api-uv-cache` directory. Verification command:

```sh
PYTHONPATH=/tmp/aldia-api-test-polling \
UV_CACHE_DIR=/tmp/aldia-api-uv-cache make -C backend/api lint test
```

The complete generated OpenAPI matched the pre-refactor JSON snapshot, including
response shapes, descriptions, examples, operation IDs and auth security fields.
`documentation/api-contract.md` has no diff. Scoped `git diff --check` passed.
Final checks: ruff passed; ruff format checked 62 files; strict mypy passed for
37 source files; pytest reported **437 passed**, including 11 new cases, in
74.89 seconds. One existing FastAPI/Starlette deprecation warning recommends
`httpx2`; no dependency was added. The unchanged runner requires working local
socket wakeups; the sandbox verification above used the temporary polling
adapter explicitly described here.
