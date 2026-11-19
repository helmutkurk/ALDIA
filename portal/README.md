# Aldia portal

A plain JavaScript portal for exploring citizen reports on a Leaflet map. Isa owns
this folder. UI copy is Spanish; code and documentation are English. ES modules
and JSDoc keep the starter approachable without a framework or TypeScript.

## Install and develop

Use the latest Node.js 24 release (`.nvmrc`), then run from `portal/`:

```sh
nvm use
npm ci
npm run dev
```

Open <http://localhost:5173>. The map starts in Guatemala City at
`[14.6349, -90.5069]`. Vite proxies `/api` to `http://localhost:8000`; run the API
separately. There are no bundled mock reports or photographs.

`.env.example` lists optional public configuration names. For `VITE_API_BASE_URL`, leave it
unset to use `/api`. If needed, define it as a URL including the API prefix, such
as `https://api.example.org/api`, before starting Vite or building. Do not put
secrets in Vite variables: they are public browser configuration. An explicitly
empty value selects the origin root (`/reports`). No environment file is needed
for the default setup.

For a separate API origin, configure its CORS allowlist. The supplied nginx CSP
uses the same-origin `/api` proxy; a separate origin also needs explicit additions
to `connect-src` and `img-src` before deployment. Docker uses the default proxy
and does not copy environment files into either image stage.

## Pages and place search

The portal is written from scratch. Only the page structure and flows described in
`../documentation/research/reference-fixmystreet-seeclickfix.md` inform the design;
no FixMyStreet code, templates or CSS are reused. API v0.1 is binding.

- `#/`: place search above the filters, alongside the map and nearby report list.
  Selecting a list button locates its marker; **Ver reporte completo** on a list
  item or popup opens the report page.
- `#/reports/<uuid>`: large photo, category, verification and resolution chips,
  captured time in `America/Guatemala`, note, pass/fail checks, location map and
  **Volver al mapa**. The original map stays mounted: center, zoom, filters,
  reports, selection, panel scroll and keyboard focus survive the round trip.
  Direct links fetch `GET /api/reports/{id}`; failures offer retry.
- `#/panel`: `GET /api/stats` with the current map bounds and category, verification
  and resolution filters. Native HTML meters styled with CSS show all contract
  categories/states, including zero values, with explicit text counts. The
  **Descargar CSV** link sends the identical filters to `GET /api/reports.csv`,
  without the list's 500-item limit. Change filters/area on the map, then reopen
  the dashboard. No municipality, status history or editing is invented: the
  contract exposes current states only.

`VITE_GEOCODER_URL` defaults to
`https://nominatim.openstreetmap.org/search`. A configured endpoint must accept
Nominatim-compatible `q`, `format=json`, `limit=5` and `countrycodes=gt,co,mx`
parameters and return an array of `display_name`, `lat` and `lon` strings. Set the
variable before starting Vite/building; custom external origins must also be
allowed explicitly in nginx `connect-src`. A same-origin proxy URL can retain
one browser build while its upstream provider changes operationally.

**The public Nominatim service is for light use only.** Follow the
[Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/):
no autocomplete, at most one request per second **across the entire application**,
identification by Referer or User-Agent, attribution and caching. Searches here
require **Buscar** or Enter, debounce 500 ms, and start at least one second apart
per mounted search. Typing does not issue requests. Repeated queries are cached
in memory (up to 100), requests time out after 15 seconds, and stale/cancelled
responses are ignored. Results are native buttons reachable with Tab and arrow
keys; Enter/Space selects, Escape dismisses them. Map flights honor reduced motion.
The visible OpenStreetMap credit links to its copyright/attribution page.

Browser requests use the browser's User-Agent and an origin Referer under
`strict-origin-when-cross-origin`; do not suppress that Referer or try to set a
forbidden User-Agent header. Public HTTP(S) hosting is required for a meaningful
Referer. A browser-side limiter cannot enforce the aggregate limit across tabs or
users: before multi-user deployment, point `VITE_GEOCODER_URL` at a proxy with a
shared limiter/cache, a self-hosted instance or a suitable provider. Do not use the
public server for autocomplete, bulk queries or production-scale traffic. A proxy
must send an identifying User-Agent/Referer and preserve attribution.

## Commands

```sh
npm test                 # One Vitest run (API, state, contract, DOM, Leaflet, routes, pages, geocoder)
npm run test:watch       # Watch tests while editing
npm run lint             # ESLint flat configuration, zero warnings
npm run format           # Apply Prettier
npm run format:check     # Check formatting
npm run build            # Production files in dist/
npm run preview          # Local production preview on port 5173
npm run check            # lint + format:check + test + build
```

Dependencies have exact direct version pins and `package-lock.json` is included.
Use `npm ci` for reproducible installs. When deliberately updating the stack, use
`npm install --save-exact` (and `--save-dev` for tooling); let npm update the lock.
The category test reads `../documentation/api-contract.md`, so run the full test
suite from this monorepo rather than a detached copy of `portal/`.

For a manual browser review (desktop, mobile, keyboard and failure states), run
`sh tests/browser-review.sh` outside the Codex sandbox. It starts Vite and prints
the review steps; open the URL in your browser. Browser rendering and container
execution require a connected browser and a running Docker daemon respectively.

## Reports and safety

- Queries use the current bounds in `west,south,east,north` order, optional
  `category`, `status` and `resolution`, and `limit=500`. Movement and filter changes debounce
  for 300 ms. Older requests are aborted and late responses ignored. Requests
  time out after 15 seconds, including response body parsing.
- The API returns newest first; the portal preserves that order. The list and
  map show up to 500 reports. If `total` exceeds the visible count, the panel
  explains the limit and suggests narrowing the area or filters. No pagination
  is implied by the count.
- `src/categories.js` and `src/styles/tokens.css` mirror the binding documents.
  The category test catches contract drift. Unknown categories/statuses/resolutions and
  malformed responses produce a recoverable error instead of a partial map.
- Stub results say **“Verificado (prueba)”** (or the corresponding status), and
  popups explicitly state that this is not real verification. Captured times are
  formatted in Spanish in `America/Guatemala`, with the timezone stated in the UI.
- API strings use `textContent`, never `innerHTML`. Photo URLs must match a UUID
  photo endpoint on the configured API origin/prefix. Unavailable photos have a
  text fallback. CSP permits only local scripts, same-origin API/photos, OSM
  tiles and Nominatim search; Leaflet needs inline styles for positioning. Event handlers use listeners.
- Keyboard users can skip to the report list, operate native filter controls,
  focus markers, and close popups with Escape. Statuses also have text, not only
  color. List selection preserves focus; flying respects reduced-motion settings.
- On desktop, the map fills the height alongside the scrollable panel. On small
  screens, the map occupies the upper 45% and the panel scrolls below it.
- The v0 contract has no authentication. Use synthetic or consented photos only.

The tiny dictionary in `src/i18n.js` contains UI copy and date formatting;
category labels mirror the contract in `src/categories.js`. Vite inserts the document title and
no-JavaScript fallback from this dictionary. API-provided notes, check details and error
messages remain literal data and may be in the language returned by the API.

The map uses the standard [OSM tile endpoint and attribution](https://operations.osmfoundation.org/policies/tiles/).
There is no prefetch or offline tile download. The referrer policy retains the
origin on tile requests. Review OSM's service policy and capacity before scaling.

## Docker

Build with `portal/` as the context. Both build and runtime are multi-stage;
nginx runs as UID/GID 101, listens on 8080, and resolves `api:8000` through Docker
DNS when a request arrives.

```sh
docker build -t aldia-portal .
# Attach to the same Docker network as the API service named/aliased "api".
docker run --rm --name aldia-portal --network aldia -p 8080:8080 aldia-portal
```

Open <http://localhost:8080>. Requests under `/api/` retain that prefix and query
string when proxied to `http://api:8000/api/`. nginx sets a 10 MB request ceiling
(the API still enforces its own upload limit), SPA fallback, gzip, and security
headers. Built assets cache for a year with expiry; `index.html` must revalidate.
The build context excludes local environment files, dependencies and build output.

To validate the container independently of a running API:

```sh
docker run --rm aldia-portal nginx -t
curl -I http://localhost:8080/
curl -I http://localhost:8080/a/client/route
curl -i http://localhost:8080/api/health
```

## Folder map

```text
portal/
├── index.html              # Spanish document, responsive viewport, entry point
├── public/favicon.svg
├── src/
│   ├── main.js             # Retained map, route composition, request coordination
│   ├── router.js           # Hash routes, UUID validation, history listener
│   ├── report.js           # Report page, safe details, location map, retry
│   ├── dashboard.js        # Filtered stats, accessible bars, CSV link
│   ├── geocoder.js         # Explicit place search, debounce, rate limit, cache
│   ├── api.js              # Fetch, response validation, contract-shaped errors
│   ├── map.js              # Leaflet tiles, markers, popup and keyboard behavior
│   ├── panel.js            # Filters, list, live states, safe popup DOM
│   ├── state.js            # Small store and pure filter function
│   ├── categories.js       # Contract category IDs and labels
│   ├── i18n.js             # Spanish UI dictionary and date formatting
│   └── styles/
│       ├── tokens.css      # Shared design tokens
│       └── app.css         # Full-height layout and responsive/accessibility styles
├── tests/                  # Synthetic fixtures and Vitest/jsdom tests
├── vite.config.js          # Port 5173, API proxy, test environment
├── eslint.config.js        # Flat ESLint configuration
├── .prettierrc
├── .prettierignore
├── .nvmrc                  # Node 24
├── .env.example            # Optional public API/geocoder configuration names
├── package.json
├── package-lock.json
├── .dockerignore
├── Dockerfile
└── nginx.conf
```
