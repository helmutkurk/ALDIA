# Portal redesign plan (2026-11-22)

Goal: one portal that keeps every feature of the current portal (login, map with list, report page, triage,
statistics, CSV) and takes the look of the `dashboard` branch mockup (sidebar, white cards, calmer type), in the
shared Guatemala sky-blue palette of `documentation/design-tokens.md`, so the portal matches the app.

Mockup: team design canvas, page "Versión combinada" (login, map and cases, report page, triage, statistics).

## Decisions

- **Palette**: the shared tokens (primary `#2A6FA8`, brand `#4997D0`, coral accent `#FF7A59`, status amber /
  violet / green / gray, red for rejected). The sidebar uses the dark bar value `#0B2A40`.
- **Surfaces**: light neutral page background with white cards and a 1 px border. The shared tokens suggest
  `card #EAF4FB` filled tiles; white cards keep the dense staff screens calmer. To agree with the app team.
- **Type**: system font stack with Inter first when installed. No web font: the production CSP allows only
  `font-src 'self'`, and self-hosting font files would be a new asset to agree on.
- **Behavior is unchanged**: same routes, API calls, permissions and states. This is a layout and style pass.
  Every test must still pass.

## Steps

1. Tokens: replace the calm teal tokens with the shared palette; spacing, radius and type scale.
2. Shell: the top header becomes a left sidebar on wide screens (logo, Mapa, Triaje, Panel, Modo personal, help);
   on narrow screens it stays a top bar with the menu button.
3. Map page: larger map, list panel with cards, filter chips and count line restyled.
4. Report page, triage and staff login: card layout, pill buttons, clear state chips.
5. Statistics: white cards, calmer charts, KPI cards. Change vs. previous period needs a second stats request
   for the previous window (follow-up).
6. Check: `npm run check` (lint, format, tests, build), browser review on desktop and phone width.

## Not in this pass

- Change vs. previous period and sparklines on the KPI cards (needs an extra request per card or an API field).
- Dark mode.
