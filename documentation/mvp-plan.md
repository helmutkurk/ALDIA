# Local MVP plan (2026-11-19 night)

Goal for the morning of 2026-11-20: **app, API, verifier and portal running together on a laptop**, one real flow end to end,
demoable with `make seed`. Not a goal tonight: writing new tests, polishing docs, anything outside the four areas.
(Keep existing checks green; run only the checks of the area you touched before each commit.)

## Definition of "MVP local" (acceptance, in order)

1. **Boot without Docker**: one command starts verifier, API (SQLite) and portal dev server; `make seed` loads demo reports.
2. **Portal works in a real browser**: map loads reports (clusters/pins), filters, list, report page with photo and timeline,
   dashboard numbers and CSV, staff mode with a token: a state transition shows up in the timeline.
3. **API + verifier**: a report created by `curl`/the app with a real JPEG is verified by the stub, stored with EXIF stripped,
   appears in the portal, and a retry with the same idempotency key creates nothing new.
4. **App**: builds and runs on at least one target available on the machine (Flutter web or desktop if no emulator), talks to the
   local API: wizard completes, result screen shows the verifier feedback, "Mis reportes" shows the new report. On Android/iOS it
   is verified by Helmut tomorrow (no emulator on this laptop).
5. `main` and `develop` identical, green CI.

## Status on 2026-11-19 (honest)

Done and merged: code for all four areas, contract v0.2, UI restyle, seed data, CI. Passing unit tests: API 358, verifier 27,
portal 110, app 91. **Not verified**: nothing has been run end to end in a browser, on a device, with Docker or PostgreSQL.
The verifier is a stub (it classifies nothing); a real model is Lorenz's work. Citizen login by phone and push are not built;
staff access is a shared provisional token.

## Backlog (strict order, one item at a time)

1. `scripts/dev-local.sh` + `make dev-all`: start verifier, API on SQLite, portal; seed; print URLs; stop with Ctrl-C.
2. Drive the portal in a real browser (Chrome extension): fix every bug found on the acceptance items 2 and 3 (screenshots in
   the log). Mobile width too.
2b. **App UI parity with the SeeClickFix reference**: follow `documentation/ui/app-reference-seeclickfix.md` (task list at its end:
   wizard order, location with address search, category search, nearby cards, new bottom navigation, Avisos and Perfil).
   Principles only, Aldia name/copy/colors, no copied assets.
3. Create a report with a real JPEG through the API as the app does (multipart, idempotency key); fix what breaks.
4. App: find a runnable target (`flutter devices`); if none, add the `web` platform (do NOT commit generated platform folders you
   do not need) and run the wizard against the local API; fix crashes. Record what only a phone can verify.
5. Replace the shared staff token with real staff users (hashed passwords, HttpOnly session cookie, roles operator/supervisor),
   keeping the old token only in dev mode behind a flag.
6. Citizen login by phone code behind an interface with a fake provider (no real SMS), API and app wired.
7. PostgreSQL: if a local server or `pglite`/testcontainers is available without Docker, run migrations and the seed on it.
8. Contract v0.3 stats from the harvest of Isabel's branch (**only after Helmut writes "Isabel OK" in the log**).
9. Update documentation for whatever changed.

## Rules (all agents and machines)

- Work on `develop`, small commits, Conventional Commits, author = the person (no agent attribution), `git pull --rebase origin develop`
  before `git push origin develop`. Never force-push, never push to `main`; release = PR `develop` → `main`, merge only with green CI.
- Never read or print environment files or tokens; no real photos of people; synthetic data only.
- No code, styles, text or images copied from FixMyStreet or SeeClickFix (licences). Do not run or install `rea` (rejected by the
  scanner, score 100). Do not touch or delete the `dashboard` branch.
- Third-party tools or repos: scan first (`hks-skillspector`); `DO_NOT_INSTALL` means no.
- If an item is blocked twice, log it and go to the next one.

## Two machines

- **This laptop (main):** backlog items 1–9, plus integration and releases.
- **Dell (optional helper):** only the `app/` area (items 4 and 6 app side) and Android/iOS platform files, after it is up to date
  with the vault guide. Each machine writes its own log: `documentation/log/<hostname>.md` (never edit the other's file).
  Contract changes go through `documentation/api-contract.md` and are announced in the log first.

## Log

Append one block per iteration to `documentation/log/<hostname>.md`: time, item, what changed, commit hash, what is next.

## Decisions taken (2026-11-19, 21:00)

- **Everything runs on the main laptop tonight** (the Dell is not used). Codex quota was reset by Helmut at 20:50 (5 h window until 01:51):
  all code work goes to Codex until Claude's window resets at 23:20. Claude then orchestrates, verifies in a real browser and reviews.
- **Phone:** Android only tonight. Plan: CI builds a debug APK as a downloadable artifact (no Android SDK on this laptop) and Helmut
  installs it on his phone; the same CI job also checks the Linux desktop build. **iOS is not possible tonight** (needs a Mac with Xcode;
  TestFlight needs a paid Apple developer account).
- **Portal and backend** run on any computer: `make dev-all` (no Docker) or `make up` (Docker). Not yet verified end to end.
- **Isabel's `dashboard` branch** adds a little our portal lacks: statistics logic (median repair time per category, frequency by category
  split fixed/open/closed, per-zone table), chart tooltips with a "see table" alternative, KPI ideas and demo data. Everything else is
  already implemented on develop. Decision: port those pieces as contract v0.3 (she stays author of the ported commit), tell her, and
  delete the branch only after the port is merged. **Helmut approved this on 2026-11-19 21:10** (he will tell Isabel; the port keeps her as commit author).
- Real staff login and phone-code login are queued after the first end-to-end run, with a fake SMS provider (nothing real is sent).

## Roles

| Role | Who | Does |
|---|---|---|
| Orchestrator | this Claude session (loop) | reads this plan, picks the next job, writes briefs, commits, merges, keeps the log, decides |
| Builder | Codex `gpt-6.1-sol` high (terminal) | all code and investigation jobs; max 2 in parallel on disjoint folders |
| Reader | Codex `gpt-6.1-terra` high | read-only review of diffs, security and contract checks |
| Quick fixer | Codex `gpt-6.1-luna` | mechanical edits, formatting, small renames |
| Verifier | Claude with the Chrome extension (after 23:20) | drives the portal in a real browser, screenshots, finds UI bugs, compares with the reference captures |
| Reviewer | Opus | final review before a release PR |
| Subagents (Claude, `[sonnet-ok]`) | only when Codex is out or the task needs Notion/Chrome tools | Notion edits, browser checks |

## Job queue (briefs in `documentation/prompts/`)

| # | Job | Folders | Status |
|---|---|---|---|
| 1 | `job-dev-local.md`: one-command local stack + smoke script + fixes | scripts, backend, portal | running (Codex) |
| 2 | `job-app-ui-parity.md`: app UI parity + Linux desktop run | app | running (Codex) |
| 3 | `job-android-apk-ci.md`: CI job that builds a debug APK artifact and the Linux build | .github, app | queued |
| 4 | `job-stats-v03.md`: contract v0.3 stats from the harvest + portal charts (with "ver tabla") | backend/api, portal | queued |
| 5 | `job-staff-auth.md`: real staff users, roles, session cookie | backend/api, portal | queued |
| 6 | `job-phone-login.md`: phone-code login with a fake provider, API and app | backend/api, app | queued |
| 7 | `job-postgres.md`: run migrations and seed on PostgreSQL without Docker if possible | backend/api | queued |
| 8 | Browser verification of the portal vs the reference captures (Claude + Chrome) | portal | after 23:20 |
| 9 | `job-mobile-release-ready.md` (replaces 3): everything for Android and iOS releases that does not depend on accounts: debug APK/AAB artifact in CI, Linux build check, release signing wired to CI secrets (placeholders, no real keys), `documentation/mobile-release.md` with the exact Play Console / TestFlight steps, iOS bundle id, Info.plist, Podfile, export options, app icons and splash assets generated in code, store listing text in Spanish. What stays for Helmut: create the Android keystore, the Apple team and certificates, and the store accounts | app, .github, documentation | queued |
| 10 | Quality pass with the Cursor skill `hks-thermo-nuclear-code-quality-review` (`~/.local/share/agent-skills/cursor-plugins/`), one job per area (api, verifier, portal, app), 2 in parallel: Reader (terra) writes the audit using that skill's standards, Builder (sol) applies only behavior-preserving restructurings, checks stay green, no file crosses 1000 lines | all four | after jobs 1-7, or earlier if the queue is empty |
| 11 | Notion hand-off: close the old tasks (Done) and create new ones per person from their roles (Notion MCP, Claude or `[sonnet-ok]` subagent; creation is allowed until 2026-11-22 on the free plan); add a status page (what exists, how to run it, what each person does next) | Notion | last |
| 12 | Delete `origin/dashboard` after the v0.3 port is merged; final release PR `develop` → `main` with green CI; update `documentation/team-update.md` (message for the team: state of the code, how to start, next tasks) and send the summary | repo | last |

Order rule: finish 1 and 2 first; run 3 and 4 in parallel next; then 5 and 6; 7 whenever a slot is free. After each job: the
orchestrator runs the checks of the touched areas, commits on develop, pushes, appends the log.

## Goals by hour (targets)

- 21:00-23:20: jobs 1, 2 (then 3, 4) with Codex.
- 23:20-01:51: Claude window 2: browser verification (job 8), fixes, jobs 5 and 6 reviewed, release PR to main if CI is green.
- 01:51-07:00: Codex window 2 and Claude window 3: jobs 6, 7, polish from the browser findings, final release PR `develop` → `main`.
- 07:00: summary in the log and by email (`hks-ausente`); `main` = `develop`.
