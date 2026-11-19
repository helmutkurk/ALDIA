#!/bin/sh
# Run outside the Codex sandbox; no browser is launched by this script.
set -eu
cd "$(dirname "$0")/.."
cat <<'STEPS'
Open http://localhost:5173 in your browser with the API running separately.
Use synthetic/consented reports only.

Review at 1280x800 and 390x844:
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
- Weekly solid/dashed SVG lines and equivalent table, category medians.
- CSV comma/semicolon download keeps all filters and uses staff header when active.
- Logout/pagehide immediately removes internal notes and staff-only controls.
- Place search requires Buscar/Enter, 500ms debounce and 1s rate limit; cache.
- Place results work with Tab/arrows/Enter/Space/Escape; attribution remains visible.
- All controls work by keyboard with visible focus; map has the list alternative.
- Reduced motion prevents animated flights; charts retain textual values.
- Slow/offline API, failed tiles, stale responses and retry states stay recoverable.
- Stub verification is explicitly identified as a test, not real verification.

Stop the server with Ctrl+C when the review is complete.
STEPS
npm run dev -- --host 127.0.0.1
