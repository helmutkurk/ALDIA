# App quality audit

Date: 2026-11-20. Scope: all maintained app source, tests, platform glue and release scripts on `develop`, reviewed as a pull request. Baseline working tree was clean. Review: `hks-thermo-nuclear-code-quality-review` (prompt only; no skill scripts executed).

## Ranked findings and restructuring plan (recorded before edits)

Finding references use the original, pre-refactor line numbers.

1. **High — wizard responsibilities accumulate in one oversized module.** `app/lib/features/report/report_flow_screen.dart:1` (1,095 lines), `:413` (location/search/map), `:955` (submission results). Navigation, lifecycle, address search, six step views and verifier results share one library. Extract cohesive widgets into location, address search, category, photo, details, duplicates and results modules. Keep the screen/controller entry points, widget order, lifecycle and callbacks unchanged. Target each extracted module below 300 lines. Shared wizard presentation belongs in `report_flow_widgets.dart`.
2. **High — home shell owns unrelated views and map orchestration.** `app/lib/features/home/home_screen.dart:1` (1,036 lines), `:376` (landing), `:517` (filters), `:678` (map). Extract navigation chrome, landing/draft banner, filters, list, map and map pins. Keep lazy tab retention, viewport request tokens, fallback behavior and reduced motion intact; avoid a shared private library that merely relocates coupling.
3. **Medium — dynamic values escape JSON boundaries into UI.** `app/lib/features/report/report_flow_screen.dart:1051` and `:1063` use `List<dynamic>` for known reports; JSON models/services use raw collections and `dynamic` (`app/lib/data/report.dart:29`, `app/lib/data/api_client.dart:47`, `app/lib/services/geocoder_service.dart:68`). Use `List<Report>` in the result view and `Object?` JSON collections with explicit casts into the existing domain models. Preserve accepted payload shapes, optional defaults and existing error policies.
4. **Medium — cluster query encoding is duplicated across transports.** `app/lib/data/api_client.dart:110` and `app/lib/data/clusters_api.dart:32` repeat bbox ordering and rounded/clamped zoom. Reuse one canonical query encoder with meaningful encoding logic; retain each public transport and its existing HTTP status/exception policy.
5. **Medium — the submission action label is an incidental conditional chain.** `app/lib/features/report/report_flow_screen.dart:179` nests ternaries for known enum cases. Replace it with an exhaustive switch so new wizard steps have one explicit label policy. Do not introduce a registry for six static views.
6. **Low — requested app quality command does not exist.** No `app/Makefile`; `make -C app lint test` fails before checks. The app is Flutter/Dart, not the Python verifier: root `Makefile:41` defines Flutter analysis/tests. Add app-local lint/test targets using these real gates. Ruff and mypy strict are not the Dart type checker; do not add Python dependencies or mislabel Flutter analysis as mypy.

## Boundaries deliberately retained

- The verifier check registry and repeated server-side image decoding are outside this Flutter area. No backend changes.
- Atomic JSON replacement and serialized outbox operations already protect persistence/order (`app/lib/features/drafts/draft_store.dart:66`, `app/lib/features/outbox/outbox_service.dart:76`). Keep this serialization, plus the geocoder rate limit. Parallel uploads, account binding, retry classification, cross-store transactions and changed failure recovery require separate behavioral decisions.
- `ReportRepository` provides local/account merging, required-login policy and notice observation; retain its public facade despite short delegation methods. Likewise preserve `LocationDiagnostics`, auth interfaces and compatibility fallbacks used by tests/embedders.
- A partial corrupt-inbox load (`app/lib/data/local_citizen_store.dart:42`) and session/storage error policies deserve separate behavior tests before changing recovery semantics. No speculative changes in this refactor.
- Hand-maintained modules over the 300-line target but below 1,000 (controller 425, theme 317, mine view 318) are cohesive enough to leave alone. Generated platform metadata/assets are not decomposed for line count.
- No API contract, endpoints, public entry points, UI copy, credentials, dependencies, lockfiles or unrelated areas will change. No coordinates are added to logs; existing fallback paths do not gain raw exception logging.

## Validation

### Applied changes

All six findings received the planned restructuring or tooling correction. No behavior fixes or dependencies were added.

- Home is now 297 lines, with landing/banner, navigation, explore tabs, filters, report list, map orchestration and map presentation in separate Dart libraries. The original map state/key, request generation and fallback paths remain intact.
- The wizard screen is now 273 lines. Address search, location, category, photo, duplicates, details, result views and shared presentation have explicit owners. Every extracted module is below 300 lines. Step action labels use an exhaustive enum switch.
- Duplicate result futures/builders now carry `List<Report>`. Production Dart source has no explicit `dynamic` or raw JSON collection casts. JSON boundaries use `Object?` and the existing report/category/draft models, retaining map-copy validation, defaults and exception policies. The UIKit channel's framework-required `Any` arguments remain platform-bound and are immediately narrowed to a string; no Swift interface was changed.
- Both public cluster clients share `clusterQueryParameters`, preserving west/south/east/north ordering and rounded/clamped zoom. HTTP success/error handling remains in each original transport.
- `app/Makefile` now exposes actual Flutter lint/test targets; `app/README.md` explains their use. No Python quality gates are represented as Dart checks.
- Added 13 regression cases: three shared cluster encoding cases, transport error compatibility, two legacy/current nearby response cases, model defaults, invalid required types, two address-search lifecycle cases, two rejected-duplicate follow cases, and retained map state across navigation.

### Executed checks

- Baseline: `make -C app lint test` failed because targets did not exist. The installed Flutter launcher also failed to write engine stamps because its SDK is read-only in this sandbox.
- Used `/tmp/aldia-quality-flutter/bin/flutter`, a writable temporary launcher/cache overlay pointing to existing installed Flutter 3.47.9 artifacts. No installed SDK, dependency versions, lockfiles or global configuration were modified; no dependencies were fetched.
- `make -C app lint FLUTTER=/tmp/aldia-quality-flutter/bin/flutter`: **PASS**, no analyzer issues, including the added regression tests.
- From `app/`, `/tmp/aldia-quality-flutter/bin/flutter build bundle --debug --no-pub`: **PASS** (exit 0). This validates the Dart/Flutter bundle, not Android/iOS signing or native device behavior.
- `make -C app lint test FLUTTER=/tmp/aldia-quality-flutter/bin/flutter`: analysis **PASS**, test execution **BLOCKED**. Flutter cannot bind its test-runner socket: `Failed to create server socket (OS Error: Operation not permitted, errno = 1), address = 127.0.0.1, port = 0`. Test libraries fail during loading; no test assertions execute. A bounded retry used an app-local temporary directory after the baseline attempt also encountered temporary-storage quota exhaustion. The full suite must still be run on a host that permits the loopback socket; tests are not claimed green.
- `git diff --check -- app documentation/log/quality-app.md`: **PASS**.
- Compared original versus extracted home/wizard AST string values using the installed Dart analyzer (excluding imports/comments): **identical multisets**. This is supporting static evidence for unchanged copy/interpolation, not a substitute for widget tests.
- Measured all maintained app source (excluding generated/build files): no module exceeds 1,000 lines. The largest remaining module is the existing 461-line controller test; the largest production module is the unchanged 425-line flow controller.
- API contract diff: empty. All edits are limited to `app/`, its README and this audit. Other concurrent jobs' files were not modified. No commits, branch changes or pushes.

### Remaining verification and deliberate limits

Run `make -C app lint test` outside this restricted sandbox before approval. Ruff and mypy strict do not check the Dart app and were not installed or run. Native release scripts, signing, camera/GPS, device secure storage, live network services and visual device rendering were inspected where relevant but not executed. No environment files, credentials, tokens or personal photos were read.

Account/local lookups retain their current ordering: both API paths can invalidate auth on 401, so their independence is not established. Parallelizing them without first specifying these side effects would exceed a clearly behavior-preserving change. Cross-store atomicity, corrupt-record recovery and outbox retry semantics likewise remain separate behavior work.
