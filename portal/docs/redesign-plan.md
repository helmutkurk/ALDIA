# Portal redesign plan (2026-11-22)

Goal: one portal that keeps every feature of the current portal (login, map with list, report page, triage,
statistics, CSV) and looks like the approved mockup: team design canvas, page "Versión combinada" (login, map and
cases, report page, triage, statistics).

## Decisions

- **Palette**: the mockup's colors (navy sidebar `#0F2A44`, accent `#2F6FB0`, page `#F6F7F9`, white cards with a
  `#E4E7EC` border; states red / orange / green / gray). Four values were darkened slightly to pass the existing
  contrast tests (focus ring, "en trabajo" orange, "cerrado" gray, received series). This differs from the shared
  app palette in `documentation/design-tokens.md`; aligning app and portal is still open with the app team.
- **Type**: Inter when installed, then the system font, on a 12/13/14/16/20/28 px scale. No web font: the
  production CSP allows only `font-src 'self'`.
- **Behavior is unchanged**: same routes, API calls, permissions and states. All existing tests still pass.

## What changed

1. Tokens (`src/styles/tokens.css`) and a redesign layer loaded last (`src/styles/redesign.css`).
2. Shell: navy left sidebar on wide screens (logo, Mapa, Triaje, Panel, Modo personal, municipality card); phones
   and tablets keep the top bar with the menu button.
3. Map page: title row with place search, one filter bar, a summary strip (open, in work, resolved, median repair
   time, from `GET /stats` for the same scope), list card with thumbnails and pagination, large map card; the
   selected report floats over the map.
4. Landing (mockup "Login2"): the first screen on every load. Staff sign in (same `POST /auth/login`, same
   lockout: 5 failed attempts lock the account for 15 minutes, sessions last up to 12 hours) or continue to the
   public map without an account. A restored cookie session skips it. The portal behind it is `inert` until then.
   The sidebar has no "Modo personal" or help button: its account block shows "Iniciar sesión" (reopens this
   screen) or the signed-in user with "Cerrar sesión".
5. Report page: two-column cards.
6. Triage (mockup "Triaje2"): table with Foto, Reporte, Antigüedad (red over 3 days, amber over 1 day),
   Verificación, Asignado a (inline assignment) and Acción ("Pasar a revisión" when the move needs no note; every
   other move, with its note rules, under "Más"). The count shows on the selected tab only: a count for the other
   tab would need one more queue request per load.
7. Statistics (mockup "Panel2"): period buttons 30 días / 90 días / Todo (default 30 días; filter dates from the
   map are used as they are, with no button pressed, until one is chosen), CSV next to them, four KPI cards with the change against the previous period
   of the same length (a second `GET /stats`), weekly trend with totals, repair time per problem (median and p90),
   most frequent problems by state, age of open reports, attention times, and the category-by-state table on
   demand.

## Differences from the mockup

- "Por zona": the API has no zone breakdown, so this card shows the category-by-state table and says so.
- Triage rows show the report date and the citizen note instead of a street address (reports have none).
- Totals say "resueltos en el periodo", not "con foto de después": not every resolved report has an after photo.

## Not in this pass

- Report page state stepper.
- Dark mode.

## UI audit (2026-11-25)

- The map opens on Guatemala City. A linked view (`bbox` in the URL) is kept only when it is near the city and no wider than about one city; otherwise the default city view is used.
- While the map is hidden (phones open on the list), the visible area uses the last real map size or a phone-sized viewport, so the list, summary strip and statistics are scoped to a real area instead of one point.
- Triage switches between table and stacked rows by the card width (container query), so window zoom or a narrow window never crushes the "Reporte" column.
- Account block: name and role on one row, "Cerrar sesión" as its own button below (one row on the tablet top bar; inside the open menu on phones).
- Toolbar controls share one height (36 px on desktop, 44 px touch targets on phones): period buttons, CSV separator and download, triage inputs and buttons.
- Report page: both columns start on the same line, primary actions ("Guardar", "Asignar") are filled buttons, the test-verification notice is a calm warning box, one column on phones.
- Phones: title first, then a 2 x 2 summary strip, then the "Ver mapa" button. Tablets: summary strip on top, list and map side by side.
