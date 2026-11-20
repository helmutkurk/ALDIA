# Staff accounts and revocable sessions

Date: 2026-11-19. Status: implemented for v0.4; production deployment verification pending.

## Problem and decision

A shared staff token could not identify who changed a case or revoke one person's access.
Use named staff accounts with `operator`, `supervisor`, `admin` roles. Existing v0.2 case
permissions remain; admin inherits supervisor rights and exclusively manages accounts.
Administration is API-only for this change. Citizen authentication is outside this decision.

The binding wire interface is [contract v0.4](../api-contract.md#v04-additions-staff-accounts-and-sessions).
Passwords use argon2-cffi 25.1.0 with explicit Argon2id v19 parameters: 65536 KiB memory,
3 passes, 4 lanes, 16-byte random salt, 32-byte hash. These follow the library's
[RFC 9106 low-memory profile guidance](https://argon2-cffi.readthedocs.io/en/stable/parameters.html).
Verification uses Argon2's native comparison; unknown users perform dummy verification.
CSRF/session/header comparisons use `hmac.compare_digest` over UTF-8 bytes.

Each login creates a random 256-bit opaque id and an independent per-session HMAC-SHA256
signing key. The browser cookie is `id.signature`; SQL stores only SHA-256(id), signing
key, SHA-256(CSRF token), user reference and absolute expiry. The signing key is generated
per session, so there is no shared signing secret to provision and sessions survive API
restarts. The database is a trusted secret-bearing store and needs restricted access/backups.
Login revokes a valid presented session and rotates both cookies. Expired rows are purged
on login; logout and user updates delete sessions immediately. User disable, role change
or password reset revokes every target session; reset also clears lockout.

The session cookie is HttpOnly, Secure except exact `ENV=dev`, SameSite=Lax, host-only and
Path=/, with a 12-hour lifetime. The CSRF cookie has matching flags except HttpOnly; every
session-authenticated staff write must echo it in `X-CSRF-Token`, also matching the SQL
session digest. This binds the double-submit pair to the session. Login accepts only
same-origin/configured Origin when supplied and JSON input. Use the portal `/api` proxy
under the same origin: an unrelated API hostname's CSRF cookie cannot be read by the portal.

Auth/user events store actor, role, action, target and UTC time, with no credentials or
request payloads. Every new case transition stores the real username plus role. Historical
non-system case events use `legacy:<role>`; their original person is unknown. Development
header fallback events use `dev:<role>` and can never grant admin access.

## Bootstrap and development compatibility

`python -m app.cli create-admin` reads passwords by hidden confirmation prompt or bounded
stdin, never argv, rejects fewer than 12 or more than 1024 characters and duplicate usernames.
No default admin exists. A deployment operator can bootstrap a different admin username
for recovery if all existing admins become disabled. There is no last-admin guard or
self-service recovery/MFA in this version.

`AUTH_DEV_TOKENS=false` by default. Even when true, `ENV=dev` is required before accepting
the old header; attempts log a credential-free warning. The portal checks public auth config
before offering the fallback. The dev seed creates `operador` and `supervisor` with random
initial passwords, printed only on creation. See [demo credentials](../demo-credentials.md).

## Limits and operations

- Five failed logins lock a SQL account for 15 minutes, across direct peer IPs. Successful
  login resets failures. Locked/disabled/unknown checks still run password verification.
- A bounded in-memory sliding-window limiter permits 10 requests per normalized username
  plus direct peer IP per 15 minutes, capped at 10,000 keys (oldest keys evicted). Restart
  resets it; workers do not share it. PostgreSQL row locks preserve account failure counts
  across replicas; SQLite's process lock is for one local API worker. Add a shared limiter
  at the edge before scaling. Configure trusted proxy handling deliberately; the app does
  not read X-Forwarded-For itself.
- Use HTTPS outside dev, explicit CORS origins, no credential payload/access logging and a
  shared origin proxy. Protect auth audit and signing-key rows like other account data.
- Migration `0004` is additive. Downgrading destroys users, sessions, auth audit and report
  actor fields; report/state data remains. Backup and deployment PostgreSQL checks remain
  operational requirements. No deployment was performed in this change.
- MFA, password breach screening, distributed limiting, idle timeout, account admin UI,
  audit retention/export and live browser/PostgreSQL validation remain provisional.
