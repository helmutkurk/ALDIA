# Portal UI notes

Scope: `portal/` and this note. The binding palette is `documentation/design-tokens.md`.
The two supplied screenshots were inspected for structure only: slim navigation, map/list workspace,
compact filters, evidence beside each report, and a dashboard led by a cumulative chart with large totals.
No reference colours, branding, typography, assets or copy were reused. (Codex, 2026-11-20)

## Map workspace

- Desktop uses a 28 rem reading panel beside the map; tablets from 701–1000 px use a 44% panel beside the map.
  At 700 px and below the list comes first and a sticky **Ver mapa / Ver lista** button switches views.
  The header starts with only the brand and **Menú** button; it exposes the same navigation and supports Escape.
  **Filtrar reportes** opens a native modal bottom sheet with the existing controls, Escape dismissal and focus
  restoration. Values survive closing; crossing to tablet restores the controls to the panel. (Codex, 2026-11-20)
- The header's **Modo personal** button is the only staff disclosure trigger. The access form is hidden until
  opened; the duplicate summary inside the panel is suppressed. The header announces the expanded state.
  Authentication changes clear private details/photos and expose the current account/login controls.
- Place search is one row: labelled input and search icon button. A small `?` disclosure contains the explanation
  and OpenStreetMap attribution. Explicit submit, throttling, cancellation and keyboard results are retained.
- Estado / Categoría occupy the first filter row; Ordenar / Incluir reportes antiguos occupy the second.
  **Más filtros** starts closed and contains the detailed state, verifier, date and assignee filters, plus the
  30-day-window explanation. Active chips disappear when there are none; they retain removal controls otherwise.
- The count remains **1 a 25 de N reportes**. Rows have a neutral inline SVG category icon and title, relative
  `<time>` (for example **hace 3 días**) with its exact Guatemala-local date in `title`, state dot and word,
  and notes clamped to two lines. The right-hand thumbnail is 72×72, rounded, lazy-loaded and cover-cropped.
  HTML dimensions and a placeholder background reserve its space; missing, unsafe or failed photos show an icon
  and **sin foto** in the same slot. The old quiet fallback used `display: none`, hiding failed thumbnails.
  **Ver reporte completo** remains a separate 44 px keyboard/touch target below the selection button.
  Selection retains the accent left bar, hover background and focused DOM button. Buttons have a 96 px minimum
  height; full row height grows with content and the separate link. Four-row visibility needs browser measurement.
- Thumbnails use the lightweight `/thumbnail` endpoint even when the list omits `thumbnail_url`.
  Authenticated photo object URLs are revoked when the owning list/page is replaced or destroyed.
- List activation selects the report, flies to its location even when its marker has not been hydrated, and opens
  evidence/details. Focused list buttons survive selection updates. Detail errors offer retry and close; closing
  restores the originating control's focus.
- At display zoom >=15 the portal requests the API's singleton mode (`zoom=17`). Lower zooms use primary-coloured
  cluster counts. Singleton pins use state colours, a white outline and a letter; selection enlarges and raises
  the pin. The state selector specificity now prevents the base grey background overriding coloured pins.
  Verifier-rejected pins use the error colour. Pending pins retain the dashed outline.
- Compact legend, textual state names, keyboard zoom, popup Escape/focus return and reduced-motion flights remain.
  Popup/side details include the photo, heuristic/stub/model explanation, checks and a link to the report/history.
  Heuristics are explicitly described as technical checks, without claiming authenticity or category recognition.

## Dashboard

- Title band → cumulative received/resolved chart and large totals → headline counters → recent activity and
  scope/export box → top-five categories and open-case ages → repair/frequency charts → SLA, overdue and other
  indicators. Detailed category/group distribution is loaded only when its disclosure opens.
- The body uses a 12-column grid, capped at 1100 px, with aligned half-width section pairs and shared card
  backgrounds, borders, padding and headings. Phone sections stack; grid children can shrink without widening
  the page. Repair and frequency charts retain **Ver tabla**, sample/null semantics and plain-Spanish municipal
  captions beneath the data. Repair captions explicitly use **hours**, matching the API and chart values.
  Top-five/state charts also explain their purpose. CSV is styled as a 44 px action. (Codex, 2026-11-20)
- Without explicit dates, the dashboard requests `include_old=true` so the main chart covers the full history.
  Explicit creation dates remain binding. CSV and chart-to-list links retain the dashboard's actual filter scope.
- Cumulative lines sum the API's weekly received/resolved buckets. Solid/circle and dashed/square encodings,
  direct labels and an equivalent weekly table make the series readable without relying on colour.
- **Últimos 7 días** uses a second request with an inclusive six-days-ago/today date range in America/Guatemala,
  retaining area, category and other non-date filters. Its displayed numbers come from that response, independently
  of the main date window. Sparklines use weekly buckets clipped by that request; the note explicitly says so.
  The contract has no daily series or update counter, so neither is fabricated. Recent-load failures have a local
  retry and do not replace the main dashboard.
- `tasa_resolucion` and `sla_cumplido` are validated as nullable 0–1 ratios, then multiplied by 100 for display.
  Zero stays zero, null stays **Sin datos**. Repair statistics retain their sample counts and null durations.
- Historical capture from the earlier running demo (not a measurement of the current 62-report demo):
  70 total, 66 received, 26 resolved, 12 overdue; resolution is
  26/61 = 42.6%, SLA 76.9%. The 2026-11-14–20 request returned 22 received and 19 resolved.
- Aggregate-only snapshots are in `portal/tests/fixtures/stats-*-snapshot.json`. The running process still served
  resolution percentages (42.62295… and 47.61905…), contrary to the updated contract. Regression tests preserve
  those snapshots, convert only that fixture field to the documented ratio, exercise the full API validator and
  rendering, and separately assert rejection of the stale percentage. There is no production compatibility coercion.

## Report, triage and accessibility

- The report page pairs evidence/metadata with history/staff controls on desktop and stacks them below 900 px.
  Evidence stays contained, with the existing enlarge-photo dialog, Escape/close and focus restoration.
  History has a continuous visual rail, readable event spacing and public/staff notes under each event.
- Triage adds an evidence thumbnail, category, local date, state and age before its existing assignment/transition
  forms. Review/rejected tabs retain arrow/Home/End keyboard behaviour. Empty queues explain that there is no work
  waiting; errors keep retry. Staff permissions and transition validation stay on the existing API/action path.
- Header `?` opens a short guide, also introduced on first opening staff access without stealing login focus.
  **Entendido** or Escape dismisses it; dismissal lives only in memory. No personal data or browser storage is used.
- The skip link focuses the current page or report list without changing the hash route. Focus rings remain 2 px
  with 2 px offset, white on the dark bar. The guide resets its surface focus colour correctly.
- Route `<h1 tabindex="-1">` elements keep programmatic focus for announcements without an outline. Other
  elements use `:focus-visible`; interactive keyboard focus keeps its ring. Search help, filter chips, report
  links and chart targets now reserve at least 44 px. Pagination wraps in the narrower tablet panel.
- Text uses existing contrast-tested tokens, with additional tests for focus on both surfaces and text on the pending
  pin centre. State dots/pins stay non-text encodings paired with words. Reduced-motion CSS and Leaflet flights remain.

## Module boundaries

`main.js` composes pages; `mount.js`, `selected-report.js` and `adjacent-report.js` own their separate lifecycles.
`panel.js` owns filtering/list state; `dom.js` and `report-details.js` contain shared DOM/detail rendering.
`report-row.js` owns relative dates and list content; `mobile-filters.js` owns the sheet and control relocation.
`dashboard.js` composes requests/sections; trends, recent activity, metrics and the distribution table are separate modules.
`api.js` owns transport; `api-validation.js` and `api-urls.js` own contract checks and URL policy.
Component CSS is split under `src/styles/`, loaded through `app.css` in the original cascade order.
Source modules remain below approximately 400 lines. No dependencies were added.

## Verification and remaining limits (2026-11-20)

- `cd portal && mise exec -- npm run check`: lint, Prettier, 166 tests across 20 Vitest files and production build pass.
  Regression coverage includes compact filters/notes, pin selection/distant flights, zoom-15 singleton requests,
  ratio boundaries, real-shaped aggregate rendering, recent date boundaries/local retry, help dismissal and focus.
  New coverage checks thumbnail HTML dimensions/`loading="lazy"`, safe URLs and visible fallback markup, relative
  date/title/icon markup, route heading focus, CSS focus/size/grid/breakpoint rules, menu dismissal, modal filter
  value/focus restoration, category captions/table toggles, and CSV presence. Existing token contrast tests pass
  at 4.5:1 or higher for text. Source modules remain below 400 lines. No dependencies were added.
- This follow-up was verified by reading source and running tests, as requested. The orchestrator previously
  inspected Chrome; no browser was launched and no new screenshots were produced in this pass. Actual image
  delivery from the current 62-report demo, four-row visibility, map tiles/pins, browser-native modal focus/Escape,
  chart sizing and horizontal overflow at 1440×900, 768×1024 and 390×844 remain unverified here. CSS/tests verify
  the intended layout rules, not browser geometry. Dark mode remains unimplemented.
- The earlier snapshot's API process served percentage-shaped resolution data; the current process was not
  queried in this pass. The portal still requires the contract's 0–1 ratios. Backend processes/files remain owned
  by their assigned job; invalid statistics are not silently reinterpreted.
- `portal/tests/browser-review.sh` contains the manual review and screenshot checklist for the already-running stack.
  Save screenshots in the repository's git-ignored `.local/shots/` directory.
