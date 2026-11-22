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
4. Staff login: split screen while the login form shows.
5. Report page: two-column cards. Triage: table-like rows. Statistics: KPI cards first, then the trend, then cards.

## Not in this pass

- Change vs. previous period on the KPI cards (needs a second stats request or an API field).
- Report page state stepper and the triage column header from the mockup (need markup changes in report.js and
  triage.js).
- Dark mode.
