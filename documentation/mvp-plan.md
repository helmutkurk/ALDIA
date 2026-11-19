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
