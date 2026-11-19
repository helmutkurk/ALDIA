# portal

ALDÍA government portal: a live map of verified street reports, a work queue by priority, and the
history of each case with its before and after photos. Plain JavaScript (ES modules), no build
step and no npm dependencies. UI text in Spanish (Guatemala).

## Run it

```bash
cd portal
npm start          # http://127.0.0.1:5173 with synthetic demo data
npm test           # node:test, no dependencies
```

Node 22 or newer. To use the backend instead of demo data, open
`http://127.0.0.1:5173/?source=api&api=<base url>`. The contract is in
[`docs/api-contract.md`](docs/api-contract.md).

## What it does

- **Map**: every case at its place. Color = status, number = independent neighbors who reported
  it, pulsing ring = dangerous. Nearby cases join into a bubble with a count when zoomed out.
- **Top numbers**: open cases, new reports (24 h), dangerous cases nobody has looked at, cases past
  their deadline, cases fixed and verified (30 days), average repair time.
- **Filters**: open / fixed / closed / all, category, period, urgent or overdue only, search by
  case number, address or zone.
- **Queue**: open cases by priority (severity, neighbors, age, near a school or hospital).
- **Case**: before and after photos, credibility, status change with a note, full history.
  The government cannot set "fixed": only a verified after photo closes the case.
- **Live**: polls every 15 s and shows a notice for each new report.
- **Export**: GeoJSON and Open311 (GeoReport v2) of the visible cases, without reporter ids.
- **Statistics page** (`#estadisticas`): repair time per problem type (median), most frequent
  problems (fixed / open / closed), new vs fixed cases per week, share fixed within the deadline
  per severity, share of repairs whose after photo failed, and a table per zone. Period: 30 days,
  90 days or all. Every chart has a hover tooltip and a table view.

## Decisions

- **Map**: Leaflet 1.9.4 with OpenStreetMap tiles, loaded from unpkg with a pinned version and an
  integrity hash. FixMyStreet does the same with OpenLayers + OpenStreetMap (Google Maps is only an
  optional map type there). Reasons: no API key or billing account for the MVP, OpenStreetMap
  covers Guatemala City well enough for a demo, and `src/ui/map-view.js` is the only file that
  touches the map, so a Google Maps adapter can replace it later. The OpenStreetMap tile server is
  for development and demos only; production needs a tile provider or Google Maps (decide with
  costs).
- **FixMyStreet**: concepts only, no code. Its code is AGPL-3.0 and a Perl application; the team
  agreed not to fork it (2026-11-19). Taken: open / fixed / closed status groups, nearby
  duplicates, Open311 export.
- **Colors**: celeste and white of Guatemala's flag, navy header, quetzal green for verified fixes
  (`src/styles/tokens.css`). Provisional, to agree with `app/`.

## Layout

```
index.html            page shell
src/main.js           wiring: data source, state, rendering
src/config.js         demo or API, map tiles, polling
src/domain/           pure logic (tested): schema, statuses, cases, priority, metrics, filters, exports, stats
src/data/             mock-source.js (synthetic Guatemala City data), api-source.js (backend)
src/ui/               map-view.js (map adapter), views.js, detail-view.js, stats-view.js, dom.js, format.js
src/styles/           tokens.css (palette), app.css
tests/                node:test suites
scripts/serve.mjs     local static server (127.0.0.1 only, strict CSP)
docs/api-contract.md  what the portal expects from backend/api
```

## Not done yet

- Login for government users (the API source already sends cookies; the backend owns sessions).
- Tile provider for production, heatmap layer, English switch.
- Assigning cases to crews; deadlines per category agreed with a municipality.
- All data is synthetic until the backend stores real reports with faces and plates blurred.
