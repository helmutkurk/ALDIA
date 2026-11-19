# Portal UI notes (restyle of the map page and dashboard)

Scope: `portal/` only. Brand tokens are unchanged (`portal/src/styles/tokens.css`, `documentation/design-tokens.md`).
The restyle is an extension of an established identity (teal, system font, flat surfaces), so no new visual world
was invented.

## What was taken from the two reference screenshots (principles, not appearance)

Map page ("around"):
- One slim bar on top carries the name and the few places a user can go; everything else gets the screen.
- Left column for reading, right area for the map, both always visible on a desktop. The list is the main content, the
  map is the spatial index of the same data.
- Filters come first and are few: status, category, sort and one checkbox for old items. Rare filters are one step away.
- A single count line ("1 a 25 de 86 reportes") tells where the reader is in the list before the rows start.
- A row is title, date, a short state, and a photo when there is one. The photo is evidence, so it sits beside the text.
- Pins are large and uniform, coloured by group, so state is readable from a distance; zoom controls are big and in
  one corner.

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
- Pins 36 px with white inner ring, dark outer outline and the state letter; clusters 48 px, dark teal with a white ring.
  Zoom control 48 px, bottom right.
- Phones: list first; fixed pill button "Ver mapa" / "Ver lista" swaps list and map.

Dashboard:
- Title band, then the all-time chart. The "all time" series is the cumulative sum of `weekly` of the current scope
  (default scope can be a 30-day window), so it is labelled "Acumulado en el periodo consultado". The end numbers are
  `recibidos` and `resueltos` from the same response. Lines differ by dash and end marker, not colour alone; a weekly
  table sits in a disclosure as the text alternative.
- "Última semana": the contract has no daily series, so there is no honest "last 7 days". The block shows the latest
  ISO week and sparklines over the last 8 weeks for Recibidos and Resueltos only. "Actualizaciones" (updates) has no
  source and is omitted. Suggested contract addition: a `daily` array and an `updates` count in `/api/stats`.
- Top 5 categorías from `by_category`; ages of open reports; v0.2 indicators in the same card style; state-group bars;
  category x group table; CSV export moved into an "Exportar datos" box.

## Derived tokens added (portal only)
`--header-height`, `--radius`, `--radius-sm`, `--shadow-raised`, `--series-received` (= primary), `--series-resolved`
(= state resolved green), `--on-primary`, `--accent-text`. Not shared with the app.

## Skill sources used
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
behaviour in older browsers (the phone map/list swap depends on it), and contrast measured by tool. Use
`portal/tests/browser-review.sh` steps at 1280x800 and 390x844.
