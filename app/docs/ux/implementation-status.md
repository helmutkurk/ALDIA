# UX implementation status (Phase 3)

Hand-off for people and agents. Updated 2026-11-21 (Fernando's session). Read this first, then
[`documentation/decisions/ux-2026-11-21.md`](../../../documentation/decisions/ux-2026-11-21.md) for the why.

## How we got here

| Phase | What | Where | Status |
|---|---|---|---|
| 1 | UX specs from the code and docs: flows, screens with states, open decisions, app/portal shared items, design direction | `app/docs/ux/*.md` (PR #21) | done |
| — | Team decisions on the ★ questions, Explorar map and the name | `documentation/decisions/ux-2026-11-21.md` (PRs #21, #22) | done |
| 2 | Low-fi wireframes + clickable prototype (3 flows, 33 screens with empty/loading/error states) | Figma "Aldia - prueba MCP", page "Wireframes low-fi" | done, approved by Fernando |
| 2 | Usability test kit (3–5 participants, 8 tasks) | [`usability-test.md`](usability-test.md) (PR #22) | kit ready, **sessions not run yet** |
| 3 | Implement the design in the Flutter app, one PR per step | see below | steps 1–3 done |

Also merged today: PR #23 (app name shown as **AlDía**), PR #18 (simpler report flow, login first, MVP test account,
design-review improvements; rebased onto the split screens by merging `develop` into it).

## Phase 3 plan

Each step: one PR into `develop`, format + analyze + tests green, a visual check with real fonts at 390×844
(throwaway render test, images in the git-ignored `.local/shots/`), merge only after Fernando says so.

| Step | Scope | PR | Status |
|---|---|---|---|
| 1 | Design tokens: sky-blue palette, coral accent, new status colors, pill buttons/chips, radii, bold type; contrast tests; `documentation/design-tokens.md` | #24 | merged |
| 2 | Shared components: `AldiaBanner` (info/warning/error) used by every wizard notice, `EmptyState` restyle, `ReportTile` restyle, coral **Reportar** pill in the bottom bar | #25 | merged |
| 3 | Explorar: full-screen map with floating controls (back, Mapa \| Lista, filter count), legend, zoom/location/layers, loading/empty/error banners, category-icon pins, filter sheet with search + category + state-group chips (`state_group`) | #26 | merged |
| 4 | Inicio: light surface, metric card (resolved count, period label, sparkline), separate loading and "no disponible" + retry states (wireframes A2, A2b). Removes the blue bar there | — | **next** |
| 5 | Sign in at send: phone sheet on **Revisar y enviar** when there is no account (B7, B8, B8b); app no longer blocks at start; Perfil "sin cuenta" variant (C6); keep the MVP test account; leave room for a future DPI method | — | to do |
| 6 | Conditional "¿Es este tu reporte?" step after Categoría, only when `GET /api/reports/nearby` returns matches; skipped offline; step counter counts shown steps (B3) | — | to do |
| 7 | Results (B9–B11), Mis reportes, Avisos (unread dot is a proposal), Perfil and the delete dialog with all their states (C1–C7); category icon grid in the wizard (B2) | — | to do |

## Known gaps: code vs. decisions (until steps 5–6)

- **Login:** the code shows "Entra a AlDía" right after onboarding and blocks the app (`REQUIRE_CITIZEN_LOGIN=true`
  app default, from PR #18). Decision 2 says sign in only at send. Do not treat the current behavior as intended.
- **Nearby step:** the wizard has no duplicates/nearby step (removed in PR #18). Decision 3 restores it only when the
  nearby endpoint finds matches. `ApiClient.nearbyReports` and `ReportRepository.duplicates` still exist for this.
- **Top bar:** `AldiaColors.bar` is a transitional blue for Inicio and the other tabs until steps 4 and 7.

## Open to-dos (outside the Phase 3 steps)

| To-do | Owner | Where it is tracked |
|---|---|---|
| Run the 3–5 usability sessions, then write `usability-results.md` and adjust the wireframes | Fernando | [`usability-test.md`](usability-test.md) |
| Portal adopts the new tokens (`portal/src/styles/tokens.css`), state wording for public pages, pins/charts colors | Isa | [`documentation/design-tokens.md`](../../../documentation/design-tokens.md), decisions 4–8 |
| Finish the **AlDía** rename: portal texts (`portal/src/i18n.js`), docs and README, store copy in `documentation/mobile-release.md`; decide on package/app ids | team (next meeting) | decision 16; Fernando's vault Kanban |
| Shared category icon set for app and portal | app + portal | [`dashboard-shared.md`](dashboard-shared.md) |
| Short display form of the report reference (cards show the full UUID) | team | [`dashboard-shared.md`](dashboard-shared.md) |
| Verification wording: the app labels only `mode: stub`, the verifier now answers `heuristic` | team | [`open-decisions.md`](open-decisions.md) #15 |
| Remaining non-blocking questions (manual review, "Otro" category, address field, consent text, push, counter period, Inicio content, language, city name, account deletion) | team | [`open-decisions.md`](open-decisions.md) |
| Flaky timing check in `test/services/geocoder_service_test.dart` (989 ms vs 990 ms under full-suite load) | app | this file |
| Real SMS/WhatsApp provider for the phone code | backend | `documentation/decisions/citizen-login.md` |

## Conventions used in this work

- UI text Spanish (Guatemala); code, docs and commits English; Conventional Commits; no agent attribution lines.
- Never color alone: state dots/pins always with the state word; text contrast ≥ 4.5:1, non-text ≥ 3:1, tested.
- Coral is never text; `brand` `#4997D0` is never behind text.
- The app name is **AlDía** in user-facing text; code identifiers (`AldiaColors`, `aldia_app`) stay.
