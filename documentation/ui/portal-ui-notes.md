# Portal UI notes (restyle of the map page and dashboard)

Scope: `portal/` and this note. The portal follows the neutral palette in `documentation/design-tokens.md`.
Decision (Helmut, 2026-11-19): simple neutral colors, with no distinctive brand color. Primary actions and header
use graphite `#1F2937`, surfaces white, and the page warm gray `#F5F5F4`. System fonts and existing behavior remain.
This supersedes the earlier teal treatment. (Codex, 2026-11-19)

## What was taken from the two reference screenshots (principles, not appearance)

Map page ("around"):
- One slim bar on top carries the name and the few places a user can go; everything else gets the screen.
- Left column for reading, right area for the map, both always visible on a desktop. The list is the main content, the
  map is the spatial index of the same data.
- Filters come first and are few: status, category, sort and one checkbox for old items. Rare filters are one step away.
- A single count line ("1 a 25 de 86 reportes") tells where the reader is in the list before the rows start.
- A row is title, date, a short state, and a photo when there is one. The photo is evidence, so it sits beside the text.
- Pins are large and uniform; state letters identify groups. Zoom controls are big and in one corner.

Dashboard:
- A title band separates "where am I" from the numbers.
- The long-term trend gets the most space: two lines (received, resolved) with the two end values written next to them.
- A short recent-activity block uses very small trend lines, each with one large number and a plain label.
- A box to choose the area and a ranked list of the most used categories finish the page.

## What was deliberately not taken
Colours, logo, fonts, icons, copy, CSS, and the cookie/advert chrome. Our palette, wording and structure are our own.
The reference's "pick your council" box has no data source here (the API has no zone breakdown), so it became a
"Zona consultada" box that states the current scope and links back to the map to change it.

## Decisions in the portal
Map page:
- `src/header.js`: shared slim header (Aldia, Mapa, Triaje, Panel, Modo personal). Links keep the filter scope; the
  current page is a filled pill (not colour alone); Modo personal opens and focuses the staff disclosure.
- Panel top is a short title band; visible filters are Estado (state group), Categoría, Ordenar, Incluir reportes
  antiguos; the other filters sit in "Más filtros" (`details`). All filter ids, names and URL behaviour are unchanged.
- Count line `1 a 25 de 86 reportes` (uses offset and shown rows).
- Rows: title (category label), date, state chip (text plus a dot), verifier badge, lazy decorative thumbnail
  (`alt=""`, hidden silently if it fails). No `innerHTML`; thumbnails reuse `createPhoto`, which validates the URL.
- Pins 36 px with neutral graphite fill, white inner ring, dark outer outline and the state letter; in-work and
  pending pins also have a dashed ring. Marker titles, accessible names, selected details and list rows retain full
  state words. Clusters are 48 px graphite circles with a white ring and a numeric count. Zoom control 48 px, bottom right.
- Status colors are functional dot fills only: open `#B45309`, in-work `#4B5563` (outlined), resolved `#15803D`, closed
  `#6B7280`, rejected/error `#B91C1C`. Every status has a word; chip text stays dark on both white and warm gray.
  Closed gray is not used as text on warm gray because that pair is below 4.5:1.
- Filters, selection outlines, list cards, KPI cards, buttons, browser theme color and favicon use neutral tokens.
  Focus is 2 px with 2 px offset; the header and dashboard band use white focus rings on graphite. Disabled buttons
  and placeholders retain readable neutral text.
- Phones: list first; fixed pill button "Ver mapa" / "Ver lista" swaps list and map.

Dashboard:
- Title band, then the all-time chart. The "all time" series is the cumulative sum of `weekly` of the current scope
  (default scope can be a 30-day window), so it is labelled "Acumulado en el periodo consultado". The end numbers are
  `recibidos` and `resueltos` from the same response. Neutral lines differ by dash and end marker (circle/square), with direct end labels; a weekly
  table sits in a disclosure as the text alternative.
- "Última semana": the contract has no daily series, so there is no honest "last 7 days". The block shows the latest
  ISO week and sparklines over the last 8 weeks for Recibidos and Resueltos only. Sparklines repeat the solid/circle
  and dashed/square encodings, with each series named beside its value. "Actualizaciones" (updates) has no
  source and is omitted. Suggested contract addition: a `daily` array and an `updates` count in `/api/stats`.
- Top 5 categorías from `by_category`; ages of open reports; v0.2 indicators in the same card style; state-group bars;
  category x group table; CSV export moved into an "Exportar datos" box.
- Category frequency uses solid graphite (Resueltos), diagonal hatching (Abiertos), and white with an outline
  (Cerrados), with matching legend swatches and per-row written counts. Repair bars are graphite with written hours.
  Detailed group distributions use solid, diagonal, horizontal, dots, crosshatch and outlined fills, alongside
  labelled count columns. SVG pattern ids are unique across all charts; tables and keyboard tooltips remain available.

## Portal tokens
Shared neutral values, `--on-primary` and `--focus` mirror `documentation/design-tokens.md` in `src/styles/tokens.css`.
Portal-only layout tokens: `--header-height`, `--radius`, `--radius-sm`, `--shadow-raised`.
Data series: `--series-received` (= primary graphite), `--series-resolved` (= muted graphite).
Functional aliases: `--success` (= resolved), `--danger` (= rejected/error); pending dots use the documented open color.
There is no decorative accent token. Status colors do not fill map pins or data charts.

## Verification (2026-11-19)
- `cd portal && mise exec -- npm run check`: lint, formatting, Vitest and production build pass.
- `tests/contrast.test.js` reads the CSS tokens and resolves aliases, linearizes sRGB, computes WCAG relative
  luminance, and asserts text foreground/background pairs at least 4.5:1. It covers main/muted text, links, buttons,
  header, data-series labels, errors and status colors on white. Status words on warm gray use main text.
- Dashboard tests also check direct labels, circle/square markers, neutral fills and unique/resolvable pattern ids.
- No legacy teal or decorative amber hex values remain in `src/` or `index.html`; the documented functional
  open-status color is retained. No dependencies were added.

## Skill sources used
- `impeccable/reference/colorize.md` (neutral pass): semantic roles, non-color encodings and measured contrast.
- `impeccable/reference/new-work.md`: decided this is an extension of an established surface (inherit, no new identity).
- `impeccable/reference/craft-floor.md`: contrast, spacing, type, states, browser surfaces (focus, selection), plus the
  "refuse" list. The brief explicitly asked for big numbers and sparklines, so those two items were kept, minimal and
  with text equivalents; no eyebrows, gradients, nested cards or coloured side borders.
- `impeccable/reference/polish.md`: system consistency, loading/empty/error states, touch targets, responsive pass.
- `impeccable/reference/audit.md`: checklist for accessibility, responsive, theming and implementation integrity.
- `anthropics-skills/hks-frontend-design/SKILL.md`: restrained typography (one system family, clear scale, no all-caps
  labels), structure that carries information, and no template chrome.
Detector scripts and `impeccable install` were not run (no network use).

## Not verified
No browser QA was possible. Unchecked: real rendering of the header on 390 px width (two rows assumed, map height uses
`100dvh - 6rem`), pin outline against OSM tiles, Leaflet zoom control overrides, chart tick sizes on phones, `:has()`
behaviour in older browsers (the phone map/list swap depends on it), rendered SVG patterns/direct labels, keyboard
focus placement, and contrast of raster map tiles. Token-pair text contrast is automated above. Use
`portal/tests/browser-review.sh` steps at 1280x800 and 390x844.
