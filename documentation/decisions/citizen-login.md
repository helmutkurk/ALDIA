# Citizen phone login (v0.5)

Status: implemented for development, 2026-11-20. Real delivery and production rollout remain unconfigured.
Binding wire interface: [contract v0.5](../api-contract.md#v05-additions-citizen-phone-verification-no-delivery-service).
Staff accounts, cookies, roles and CSRF remain governed by [staff auth](staff-auth.md).

## Decision and development flow

Use a six-digit phone code instead of email/password at the final report step.
The app defaults to Guatemala (+502, eight national digits). The API accepts normalized
E.164 and defaults bare eight-digit input to Guatemala. A verified installation gets a
random opaque bearer token for 90 days. A new verification rotates only that citizen's
session on the same installation; other installations remain signed in. Logout deletes
the current session immediately. The client sends its securely retained random UUID in
`X-Device-ID` with the bearer. This is installation binding, not hardware attestation;
copying both credentials permits replay. Use HTTPS outside local development.

`REQUIRE_CITIZEN_LOGIN=false` preserves anonymous submissions. When true the API requires
citizen credentials; the app's matching `--dart-define=REQUIRE_CITIZEN_LOGIN=true` blocks
submission until verified. The API is authoritative even if the app flag differs.
Anonymous historical reports cannot be claimed through login or an idempotency key.
Authenticated reports remain owned across token rotations and verified devices. Offline logout removes credentials locally and reports that server revocation could
not be completed; re-verifying the same installation rotates the old session.
Queued uploads use the account active when they are sent; switching accounts can
change the owner of an unsent item, while a retry of an already accepted item under
a different owner is rejected by the API. Review/remove queued items before switching
accounts; per-account queue binding remains provisional. Local
items merge with authenticated reports; anonymous items remain local to their original
installation. Staff credentials never substitute for citizen credentials.

`SmsProvider` is a Python Protocol. `NullSmsProvider` is the default and refuses delivery;
no usable challenge is saved when delivery refuses. `ConsoleSmsProvider` exists only for
exact `ENV=dev`; it logs a loud DEV ONLY banner and the code, without a destination phone.
It makes no network calls. Nothing is sent to real numbers. Production rejects console
configuration. A future real provider (Twilio SMS or Meta WhatsApp) requires an explicit
team decision and another reviewed implementation; neither SDK, credentials nor outbound
integration is included here. A request still returns 202 when delivery is unconfigured.

## Persistence and privacy

- `PHONE_HASH_KEY` is an external server secret of at least 32 characters. Only exact
  `ENV=dev` permits a known insecure fallback. Production has no fallback. Mandatory
  login without a key fails startup; optional anonymous reports remain usable without
  configuring citizen auth. OTP requests without a key return the same 202; verification
  returns 503 `citizen_unavailable`.
- SQL stores only a domain-separated HMAC-SHA256 of the normalized phone plus last two
  digits, never the full number. Raw numbers exist transiently while validating/delivering.
  Citizen ids are keyed hashes of random identifiers, independent from the phone hash.
  Reports store nullable internal citizen ids. No API, export or staff view exposes them.
- OTPs are keyed digests incorporating a random challenge nonce; bearer tokens are stored
  only as SHA-256 digests; device UUIDs as domain-separated keyed digests. A SQL-only leak
  cannot cheaply enumerate a six-digit OTP. Leaking the HMAC key enables phone enumeration
  against leaked rows; restrict database, secret manager and backup access independently.
- Last-two digits are support hints, not identifiers. Phone hashes and report ownership
  remain pseudonymous personal data, especially when linked to report locations/times.
  Hashing is not anonymization or permission to publish those values.
- Optional aliases are private by default. Explicit `alias_public: true` publishes only a
  display-name snapshot on subsequently created reports. Existing public snapshots do not
  disappear on logout or a later private login. Do not use a real name or phone as an alias
  unless the person explicitly wants it public. Self-service account/profile deletion and
  retrospective alias removal are not implemented in this version.
- Auth responses, including errors/validation errors, use `Cache-Control: no-store`.
  The app retains token, device id, expiry and masked last-two display in secure storage;
  it does not persist the raw phone or OTP. Normal request logs contain route templates,
  status and duration only. Never enable request-body/header logging at a proxy.
- Console codes are an explicit development-only credential leak: access to the private
  API console permits signing in. Use only synthetic inputs, never share/capture those logs,
  and keep them out of CI artifacts. Test providers capture codes in memory without logs.

Key rotation is not transparent: old phone/device hashes cannot be recomputed without
raw numbers. Provision a stable key through the secret manager, retain controlled backups,
and plan explicit re-verification, session revocation and ownership migration before rotation.
Do not silently replace the key or enable the development fallback in a deployment.

## Abuse controls and atomicity

Codes expire after ten minutes and allow five failed attempts, compared in constant time.
Unknown, consumed, wrong-device, exhausted and expired codes share one generic 401 error.
Resends invalidate previous challenges, wait 60 seconds, and preserve failed-attempt counts
while active. Requests always return the same 202 regardless of known account, cooldown,
rate suppression or delivery availability. The request path never looks up account existence.

Reuse the bounded sliding-window limiter with independent budgets: request three/phone
and ten/direct-peer-IP per 15 minutes; verify ten/phone and thirty/IP per 15 minutes.
Request suppression stays 202; verification limits return 429 with numeric Retry-After.
Do not trust `X-Forwarded-For`. These budgets are per process, reset on restart and fail
closed at 10,000 live keys per budget. A shared edge limiter is required before scaling.
Persistent challenge attempts and consumption are serialized by a local process lock on
SQLite and a PostgreSQL transaction advisory lock across workers. OTP/session expiry is
checked on every use. Expired challenges are purged on accepted request handling; expired
sessions on successful verification. Account/alias retention and scheduled cleanup need an
operational retention decision before real users; no cron or automatic account deletion
is supplied. A database failure after console output can yield an unusable development code.

Idempotency retains the 24-hour original-report behavior, now checking ownership before
both the early replay and the transactional replay. A different citizen, or anonymous
caller replaying a citizen's key, gets 409 without report data. This prevents ownership
transfer or using a known retry key to discover a hidden/private association.

## Verification and remaining work

SQLite integration tests cover uniform responses, expiry/consumption, attempts, resend,
phone/IP budgets, session expiry/rotation/logout, multiple devices, ownership, anonymous
and required-login modes, aliases, CORS, private errors/logs and migration drift/round trips.
App tests use fake auth, HTTP and secure storage, including expired-code and offline states.
See [testing](../testing.md) for commands and the local manual flow.

No real provider, SMS delivery, WhatsApp integration, push, phone-number reassignment
protection, device attestation, lost-device recovery, deletion UI or live PostgreSQL/mobile
validation is claimed. A number's eventual new owner can gain access to that number's
report history after re-verification; account recovery/retention policy must address this
before production. Report photos and public descriptions remain public independently of login.
