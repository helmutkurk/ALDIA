# Portal UI notes

Scope: `portal/` and this note. The binding palette is `documentation/design-tokens.md`.
The two supplied screenshots were inspected for structure only: slim navigation, map/list workspace,
compact filters, evidence beside each report, and a dashboard led by a cumulative chart with large totals.
No reference colours, branding, typography, assets or copy were reused. (Codex, 2026-11-20)

## Map workspace

- Desktop uses a 28 rem reading panel beside the map; tablets from 701–1000 px use a narrower balanced split.
  At 700 px and below the list comes first and a fixed **Ver mapa / Ver lista** button switches views.
- The header's **Modo personal** button is the only staff disclosure trigger. The access form is hidden until
  opened; the duplicate summary inside the panel is suppressed. The header announces the expanded state.
  Authentication changes clear private details/photos and expose the current account/login controls.
- Place search is one row: labelled input and search icon button. A small `?` disclosure contains the explanation
  and OpenStreetMap attribution. Explicit submit, throttling, cancellation and keyboard results are retained.
- Estado / Categoría occupy the first filter row; Ordenar / Incluir reportes antiguos occupy the second.
  **Más filtros** starts closed and contains the detailed state, verifier, date and assignee filters, plus the
  30-day-window explanation. Active chips disappear when there are none; they retain removal controls otherwise.
- The count remains **1 a 25 de N reportes**. Rows have a category title, Guatemala-local `<time>`, state dot and
  word, a single-line note, and a 96×72 decorative lazy thumbnail on the right. The adjacent **Ver reporte**
  link remains a separate keyboard target below the thumbnail. Missing photos reserve the same layout.
  Seven-rem rows and compact controls target four complete rows within 1440×900; this still needs browser measurement.
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
- All-time values observed in the running demo: 70 total, 66 received, 26 resolved, 12 overdue; resolution is
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
- Text uses existing contrast-tested tokens, with additional tests for focus on both surfaces and text on the pending
  pin centre. State dots/pins stay non-text encodings paired with words. Reduced-motion CSS and Leaflet flights remain.

## Module boundaries

`main.js` composes pages; `mount.js`, `selected-report.js` and `adjacent-report.js` own their separate lifecycles.
`panel.js` owns filtering/list state; `dom.js` and `report-details.js` contain shared DOM/detail rendering.
`dashboard.js` composes requests/sections; trends, recent activity, metrics and the distribution table are separate modules.
`api.js` owns transport; `api-validation.js` and `api-urls.js` own contract checks and URL policy.
Component CSS is split under `src/styles/`, loaded through `app.css` in the original cascade order.
Source modules remain below approximately 400 lines. No dependencies were added.

## Verification and remaining limits (2026-11-20)

- `cd portal && mise exec -- npm run check`: lint, Prettier, 160 tests across 19 Vitest files and production build pass.
  Regression coverage includes compact filters/notes, pin selection/distant flights, zoom-15 singleton requests,
  ratio boundaries, real-shaped aggregate rendering, recent date boundaries/local retry, help dismissal and focus.
- Browser access returned **The browser access host is unavailable**. No browser was launched inside the sandbox,
  and no screenshots were produced. Four-row visibility, map tile/pin appearance, chart sizing and actual overflow
  at 1440×900, 768×1024 and 390×844 remain unverified. Dark mode remains unimplemented.
- The active API process must pick up the backend ratio fix before live `#/panel` can pass the validator. Backend
  processes/files were left to their assigned job. The portal does not silently reinterpret invalid statistics.
- `portal/tests/browser-review.sh` contains the manual review and screenshot checklist for the already-running stack.
  Save screenshots in the repository's git-ignored `.local/shots/` directory.
