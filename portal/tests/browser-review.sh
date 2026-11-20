#!/bin/sh
# Run outside the Codex sandbox; no browser is launched by this script.
set -eu
cd "$(dirname "$0")/.."
cat <<'STEPS'
Open http://localhost:5173 in your browser with the API running separately.
Use synthetic/consented reports only.

Review at 1440x900, 768x1024 and 390x844.
Save map, dashboard, a synthetic report and staff-triage screenshots at each size
in the repo-root git-ignored .local/shots/ directory (e.g. map-1440.png).
At 1440x900 measure that at least four complete report rows are above the fold.
The list should start after two filter rows and the closed Más filtros disclosure.
Ensure the API was restarted with the ratio fix: tasa_resolucion must be 0–1.

Checklist:
- Desktop map/list layout; mobile list-first layout and map toggle; no overflow.
- All filters, active chips and count; URL hash reflects edits and browser history.
- Default 30 days, include-old toggle, server pagination and sort ordering.
- Move the map after changing pages: the list returns to page one.
- Cluster count click zooms; maximum zoom shows identified members/limitation.
- Pin/list selection opens a side panel without navigation; state labels/letters.
- Modo personal works on every route; token input clears after activation.
- Public view has no actions; operator and supervisor offer different targets.
- Every legal transition, closing reason, forward skip note, duplicate master UUID.
- Supervisor rejection override requires internal note; failed actions explain 409/401/503.
- Assignment, clearing assignment, queue tabs, age badges and pagination.
- Detail photograph, modal zoom/Escape/focus, missing-photo fallback and timeline.
- Previous/next within filter, including across a server page boundary.
- Nearby duplicate thumbnails and selection of a master report.
- Dashboard counts, percentages/nulls, n, age buckets, category/group distribution.
- Dark bar, calm teal actions, white surfaces and cool-grey background; system fonts.
- Status-coloured pins at zoom >=15; selected pin enlarged; primary cluster counts; compact legend.
- Weekly solid/circle and dashed/square series, direct labels and equivalent table.
- Sparklines keep solid/circle and dashed/square encodings with named values.
- Category stacks use primary/hatching/outlined fills matching the legend and written counts.
- Detailed group patterns stay visible; no broken SVG references after routing/filter changes.
- KPI strip and category medians stay legible; check 2px focus rings including dark bands.
- CSV comma/semicolon download keeps all filters and uses staff header when active.
- Logout/pagehide immediately removes internal notes and staff-only controls.
- Place search requires Buscar/Enter, 500ms debounce and 1s rate limit; cache.
- Place results work with Tab/arrows/Enter/Space/Escape; hint and attribution are reachable via ?.
- Header ? guide is dismissible/reopenable; staff login focus is retained; no browser storage.
- Skip link focuses the current page without routing back to the map.
- Seven-day values use their own dated request; weekly sparkline grouping is explicit.
- All controls work by keyboard with visible focus; map has the list alternative.
- Reduced motion prevents animated flights; charts retain textual values.
- Slow/offline API, failed tiles, stale responses and retry states stay recoverable.
- Stub verification is explicitly identified as a test, not real verification.

Use the existing stack; this script does not start or stop any server.
STEPS
