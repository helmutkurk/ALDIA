# Aldia portal

A plain JavaScript municipal portal with Leaflet, ES modules and JSDoc. Isa owns
this folder. UI copy is Spanish; code and documentation are English. The binding
API contract is `../documentation/api-contract.md`, including v0.2, v0.3 and v0.4.
The portal is original work based on our own clean-room behavior notes;
no FixMyStreet source, CSS, templates or translations are used.

## Install and develop

Use Node.js 24 (`.nvmrc`), then run from `portal/`:

```sh
nvm use
npm ci
npm run dev
```

Open <http://localhost:5173>. The map starts in Guatemala City at
`[14.6349, -90.5069]`. Vite proxies `/api` to `http://localhost:8000`.
Run the API separately; development and production include no bundled reports or
photographs. Tests use synthetic fixtures and mocked fetch.
For HTTP development the API needs `ENV=dev` so its session cookie can work
without HTTPS. Migrate and bootstrap an admin with
`uv run python -m app.cli create-admin` from `backend/api/`, or seed the dev-only
`operador`/`supervisor` accounts. The seed prints a newly generated password once;
there is no published or built-in password. Use **Modo personal → Iniciar sesión**.

`.env.example` lists optional **public** build-time names. Unset
`VITE_API_BASE_URL` uses `/api`; an explicitly empty value uses the origin root.
A separate origin must include the API prefix (for example,
`https://api.example.org/api`) and requires a matching API CORS allowlist and
explicit nginx CSP `connect-src`/`img-src` entries. Staff CORS needs explicit
origins, credential support, `X-CSRF-Token`, `Content-Type`, POST and PATCH.
The staff portal must share the cookie origin through the existing `/api` proxy:
double-submit CSRF reads the API's `aldia_csrf` cookie, which cannot be read from
an unrelated API hostname. Public cross-origin reads remain possible with CORS.
Never put a password or staff token in a Vite variable: build-time values are public.

## Pages and staff mode

- All routes share the slim header from `src/header.js` (Mapa, Triaje, Panel, Modo
  personal). UI rationale and unverified points: `../documentation/ui/portal-ui-notes.md`.
- `#/`: place search, filter controls (Estado, Categoría, Ordenar and the old-reports
  checkbox visible, others under "Más filtros"), count line `1 a 25 de 86 reportes`,
  rows with state chip and lazy thumbnail, active-filter chips and result count,
  independently paginated list (25 reports), clustered viewport map. Clicking a
  pin or selecting a list item opens the side panel without changing route.
  Cluster counts zoom in; at maximum zoom their identified reports appear in the
  side panel. Singletons use their municipal state group, a letter and an
  accessible text label: open red, in work orange, resolved green, closed grey,
  pending outlined. The list is the keyboard alternative to the map.
- `#/reports/<uuid>`: full photograph and modal enlargement, verifier verdict and
  reasons, municipal state, timestamps in 24-hour Guatemala time, coordinates,
  location map, assignee, chronological events and nearby duplicate suggestions.
  Previous/next follows server ordering within the current viewport and filters,
  fetching adjacent pages as necessary. A direct link may require scanning list
  pages to locate its position; a report outside the filter has no neighbor.
- `#/triage`: staff queue tabs **Por revisar** and **Rechazadas por verificador**,
  server ordering and pagination, age badges, assignment and legal transitions.
  Tabs support arrow keys, Home and End. Operators cannot override rejection;
  supervisors must supply an internal reason.
- `#/panel`: title band, cumulative received/resolved chart with end numbers, last-week
  sparklines (received, resolved; the API has no daily or updates series), top 5
  categories, then server metrics, sample sizes, percentages, null/no-sample values,
  age buckets, exact category × state-group distribution, category median
  durations, weekly received/resolved SVG lines and an equivalent table.
  Category cross-tabs use separately filtered stats requests; the portal never
  derives population statistics from the current list page. CSV has a comma or
  semicolon selector and retains the same scope. Downloads use fetch with the
  session cookie when active, then a temporary object URL.

**Modo personal** is reachable on every route. Enter your username and password;
the API sets an HttpOnly session cookie and returns the account's role. The portal
restores an existing session with `/auth/me`. Operators manage ordinary cases;
supervisors and admins also override rejections, reopen closed cases and moderate.
The server checks every permission. **Cerrar sesión** revokes the server session.
Public viewers see no write controls. A separate token form appears only after
`GET /api/auth/config` reports `dev_tokens: true` (requires API `ENV=dev` and
`AUTH_DEV_TOKENS=true`). Its role selector remains a UI hint, checked by the API.
Assignment accepts a cuadrilla/responsible name (60 characters), or blank to clear.
Public notes are limited to 280 characters and internal notes to 500.

`src/states.js` mirrors all 11 states, group membership, explicit transition
edges, backward moves among active states and supervisor-only actions. Only
listed targets are offered. Closing without solution and reopening a closed
case require a public or internal reason; skipping from `en_revision` to
`en_proceso` also requires a reason. Duplicate closure has an optional reason
and a required master UUID. Hide restoration comes from the latest hide event;
without that history the portal cannot guess a legal restore target. Unlisted
forward skips are not offered. HTTP 409 explains a conflict/illegal transition;
401 requests a fresh login, 403 explains denied permission or stale CSRF, 423
explains the 15-minute account lockout, and 429 explains login throttling.

## Shared filters, ordering and map performance

Hash query parameters carry category, verifier status, legacy resolution,
municipal group/state, created-date bounds, assignee, sort and `include_old=true`,
as well as the map bbox. Unknown fields, credentials and malformed values are
discarded. Report, dashboard and back links retain this scope. Filters apply to
list, stats and CSV; they are also sent to the cluster endpoint. Clearing a chip
removes its filter. Without `created_from` the API applies the default last 30
days unless **Incluir antiguos** is checked. Day boundaries belong to the API
(`America/Guatemala`), not the browser's timezone.

List pagination uses server offsets in increments of 25. The server supplies
stable tie-breaking for `newest`, `oldest`, `updated` and `age_in_state`; the
portal preserves the returned order. Changing filters or map area resets the
page. Map and filter reads debounce for 300 ms. Requests have 15-second
deadlines, cancellation and generation guards; late responses cannot replace a
newer route or scope. A failed map pin fetch does not discard a successful list.

The cluster contract currently provides only coordinates, count and optional
first-five IDs. Singleton details are hydrated with at most six concurrent reads
to obtain their states; list-page reports are reused when available. There is no
client-side attempt to reconstruct a population of pins from one list page.

## Contract gaps and explicit limits

- User administration is available through the admin-only API; this portal has
  no account-management screen yet.
- `/reports/clusters` documents only bbox and zoom, not support for the other
  list filters. It must honor those supplied filters for map/list parity. To
  avoid singleton hydration, it should return a guaranteed report ID and group
  (or specify its high-zoom singleton shape). Optional IDs mean some pins may
  only be rendered as count bubbles. If a maximum-zoom cluster exceeds its five
  supplied IDs, the portal explicitly identifies the incomplete member list;
  exact expansion needs a cluster-members endpoint or complete IDs.
- Nearby response wrapping and thumbnail path are not specified. The portal
  expects a report array with optional `thumbnail_url`; safe report `/photo`
  and `/thumbnail` URLs on the configured API are accepted. Assignment accepts
  a report/object success or HTTP 204 because its response body is unspecified.
- The API cannot express exact list drill-downs for every dashboard number:
  multi-group open cases, verified-at presence, resolution/closure timestamp
  periods, first-response durations, SLA, age buckets and weekly periods lack
  corresponding filters. Exact category/group/rejected links work; unsupported
  metric counts remain text, with visible explanations. Their values are never
  replaced with a different metric merely to create a link.
- Zone tables and SLA calendars/pauses, bulk actions, category editing, reporter
  aliases, addresses, private identity, repair photos and notification delivery
  are outside the v0.2 API. No substitute data or unsupported write calls are
  invented.
- The server still owns CSV BOM, columns, cap, hidden-report exclusion and
  formula-injection handling. The browser passes the selected delimiter/filters.

## Security and accessibility

Passwords are cleared from the form immediately after submission and never enter
localStorage, sessionStorage, URLs, logs or the build. Session credentials remain
in the browser's HttpOnly cookie; JavaScript retains only the username/role.
The API sets Secure outside `ENV=dev`, SameSite=Lax and a 12-hour expiry.
The readable `aldia_csrf` cookie supplies `X-CSRF-Token` on writes, including
logout (login instead receives server Origin validation). Development tokens
live only in a tab-local closure and are discarded on logout/pagehide/reload.
Changing staff mode clears private detail content and map results before reloading.
All API requests use `cache: no-store`, `credentials: include` and reject redirects.
Only the explicitly enabled development fallback uses `X-Staff-Token`.
Staff photos load through authenticated
fetch with cancellable, short-lived object URLs; public photos use their safe
API URL. Photo object URLs are revoked when their view closes. Use synthetic
or consented photos for demos.

API strings use `textContent`, never `innerHTML`. Photo URLs must match an
approved UUID photo/thumbnail endpoint on the configured API origin/prefix.
Missing photos show a text fallback. There are no inline script/event handlers;
nginx CSP allows `blob:` images for authenticated staff photos; scripts remain self-only. Leaflet needs inline **styles** for positioning.
Token headers are not sent to geocoder/tile requests.

Native controls, explicit labels, live status/error messages, visible focus,
state text and marker letters support keyboard and assistive-technology users.
On mobile the list appears first and a map toggle reveals the map. Map flights
and CSS transitions honor `prefers-reduced-motion`. SVG graphs have text/table
alternatives. All UI copy lives in `src/i18n.js`, state colors in
`src/styles/tokens.css`; category labels mirror the contract.

## Place search and map services

`VITE_GEOCODER_URL` defaults to
`https://nominatim.openstreetmap.org/search`. A custom provider must accept
Nominatim-compatible `q`, `format=json`, `limit=5`, `countrycodes=gt,co,mx` and
return `display_name`, `lat`, `lon`. External origins need explicit nginx
`connect-src` permission; a same-origin proxy can change its upstream without
rebuilding the browser application.

Public Nominatim is for light use only. Follow the
[Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/):
no autocomplete, at most one request per second **across the application**,
identification, attribution and caching. Searches require Buscar/Enter, debounce
500 ms, start at least one second apart per mounted search, cache up to 100
queries in memory and time out after 15 seconds. Results support Tab, arrows,
Enter/Space and Escape. Browser requests retain their origin Referer under
`strict-origin-when-cross-origin`; do not override the forbidden User-Agent.
Before multi-user deployment use a proxy with a shared limiter/cache, a
self-hosted instance or another suitable provider: a browser cannot enforce the
aggregate service limit across tabs/users. A proxy must preserve identification
and attribution.

Tiles use the [standard OSM endpoint](https://operations.osmfoundation.org/policies/tiles/)
with visible attribution and origin Referer. There is no offline download or
prefetch. Review provider capacity before scaling.

## Checks and browser review

```sh
npm run check           # ESLint, Prettier, all Vitest tests, production build
make lint test          # Existing JS checks; tests skip environment-file loading
npm run test:watch
npm run dev
```

Tests use fake timers and mocked fetch; no live API, geocoder or photos are
required. `tests/staff-auth.test.js` covers login/logout, session restoration,
API-controlled dev fallback, admin gating, Spanish 401/403/423 and CSRF headers.
This JavaScript portal uses ESLint, Prettier and runtime payload validation;
Ruff and mypy do not apply. Shared JSDoc models live in `src/api-types.js`.
`src/api-request.js` owns HTTP policy, `src/workspace-load.js` owns list/cluster
loading, and `src/csv-export.js` owns the dashboard download lifecycle.
The quality audit and verification record are in
`../documentation/log/quality-portal.md`.
`tests/browser-review.sh` prints the desktop/mobile review checklist
and starts Vite. Run browser review outside the Codex sandbox, with the API
running separately, or use an external connected browser.

## Docker

Build with `portal/` as the context. nginx runs as UID/GID 101 on port 8080:

```sh
docker build -t aldia-portal .
docker run --rm --name aldia-portal --network aldia -p 8080:8080 aldia-portal
```

The container joins the network of the API named `api`. `/api/` retains its
prefix and query string when proxied to `http://api:8000/api/`; Docker DNS is
resolved per request. nginx supplies a 10 MB request ceiling (the API enforces
its own upload limit), SPA fallback, gzip and security headers. Hashed assets
cache for one year, index.html revalidates. Docker excludes environment files,
local dependencies and build output. The default image needs no environment
file.

```sh
docker run --rm aldia-portal nginx -t
curl -I http://localhost:8080/
curl -i http://localhost:8080/api/health
```

## Folder map

```text
portal/
├── src/
│   ├── main.js          # Retained workspace, scope, clusters, route coordination
│   ├── router.js        # UUID/hash routes and history listeners
│   ├── filters.js       # Whitelisted public filters and shareable hash codec
│   ├── states.js        # 11-state table, groups, role targets, note requirements
│   ├── staff.js         # Cookie session identity, login/logout, optional dev panel
│   ├── actions.js       # Legal state transitions, reasons, duplicate/assignment forms
│   ├── triage.js        # Queue tabs, age and pagination
│   ├── report.js        # Full details, modal photo, timeline and nearby duplicates
│   ├── dashboard.js     # API metrics, samples, SVG/tables, authenticated CSV download
│   ├── api.js           # Cookie/CSRF fetch, deadlines and validated endpoint methods
│   ├── photo.js         # Safe public images/authenticated staff blobs and cleanup
│   ├── map.js           # Leaflet viewport, clusters, pins and keyboard behavior
│   ├── panel.js         # Safe details, filters, chips and paginated report list
│   ├── state.js         # Immutable report/filter/pagination store
│   ├── geocoder.js      # Explicit searches, caching, rate limit and cancellation
│   ├── categories.js    # Contract category IDs and Spanish labels
│   ├── i18n.js          # Spanish copy and Guatemala date formatting
│   └── styles/
│       ├── tokens.css   # Shared colors and handling-group tokens
│       └── app.css      # Responsive surfaces, charts and accessibility
├── tests/               # Synthetic data, Vitest/jsdom and browser review checklist
├── index.html
├── public/favicon.svg
├── vite.config.js
├── eslint.config.js
├── package.json         # Exact dependency versions; no new dependencies for v0.2
├── package-lock.json
├── .env.example         # Public API/geocoder names; never staff credentials
├── Dockerfile
└── nginx.conf
```
