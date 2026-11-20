# Portal UI notes (restyle of the map page and dashboard)

Scope: `portal/` and this note. The portal follows FixMyStreet's structure with the calm palette in
`documentation/design-tokens.md` (decision Helmut, 2026-11-20), which replaces the neutral graphite palette of
2026-11-19. System fonts, behavior, routes and a11y features are unchanged. (Claude, 2026-11-20)

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
  current page has the orange `accent` underline plus bold weight (not colour alone); Modo personal opens and focuses the staff disclosure.
- Panel top is a short title band; visible filters are Estado (state group), Categoría, Ordenar, Incluir reportes
  antiguos; the other filters sit in "Más filtros" (`details`). All filter ids, names and URL behaviour are unchanged.
- Count line `1 a 25 de 86 reportes` (uses offset and shown rows).
- Rows: title (category label), date, state chip (text plus a dot), verifier badge, lazy decorative thumbnail
  (`alt=""`, hidden silently if it fails). No `innerHTML`; thumbnails reuse `createPhoto`, which validates the URL.
- Pins 36 px, filled with the status color (open orange, in work green, resolved blue, closed gray; pending is white
  with a dashed outline), white outline and the status letter. Marker titles, accessible names, selected details and
  list rows keep full state words; the legend dots use the same colors. Clusters are 48 px `primary` circles with a
  white ring and the count. Zoom control 48 px, bottom right, no heavy outline.
- Status in the list is a dot of the status color plus the word in normal text color. Dots and pins are non-text and
  are tested at 3:1 on white; text pairs at 4.5:1.
- Header and dashboard band use `bar` with white text; the panel header is white. Primary buttons and links are
  `primary` / `primary-dark` (links use `primary-dark` because `primary` is 4.47:1 on the page gray). `accent` marks
  only the current nav item, the selected list row, selected tabs and the dashboard band rule; never text.
  Focus is 2 px `focus` with 2 px offset (white on `bar`).
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
- Category frequency keeps solid, diagonal hatching and outline fills in `primary` (tests require these), with legend
  swatches and written counts. Detailed group distributions keep their distinct patterns.
  SVG pattern ids are unique across all charts; tables and keyboard tooltips remain available.

## Portal tokens
`src/styles/tokens.css` mirrors `documentation/design-tokens.md` (`bar`, `primary`, `accent`, status colors, `focus`).
Portal-only: `--header-height`, `--radius`, `--radius-sm`, spacing scale `--space-1..6`, `--shadow-raised`, `--success`
(#2E7D32, text-safe green), `--danger`. Series: `--series-received` (= `primary-dark`, solid, circle marker) and
`--series-resolved` (= `success`, dashed, square marker); direct end labels remain, so color is never the only cue.

## Verification (2026-11-20)
- `cd portal && mise exec -- npm run check`: lint, format, 149 Vitest tests and build pass.
- `tests/contrast.test.js` asserts every text pair >= 4.5:1 (text, muted, links, danger, success, series, on-bar/bar,
  on-primary/primary) and status dots >= 3:1 on white.

## Not verified
No browser QA was possible. Unchecked: header at 390 px, pin appearance on OSM tiles, Leaflet control overrides,
chart sizes on phones, `:has()` in older browsers (phone map/list swap), rendered SVG patterns, keyboard focus
placement, dark mode (not implemented in the portal). Use `portal/tests/browser-review.sh` at 1280x800 and 390x844.
