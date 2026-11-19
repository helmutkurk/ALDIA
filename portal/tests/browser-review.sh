#!/bin/sh
# Run outside the Codex sandbox; no browser is launched by this script.
set -eu
cd "$(dirname "$0")/.."
cat <<'STEPS'
Open http://localhost:5173 in your browser with the API running separately.
Use synthetic/consented reports only.

Review at 1280x800 and 390x844:
- Map and panel fill the viewport without horizontal overflow.
- All three filters, list selection, marker details and the photo thumbnail work.
- Type a place: no request until Buscar/Enter. Repeated submits debounce 500 ms;
  request starts stay at least a second apart. Repeating a query uses the cache.
- Place results work with Tab, arrows and Enter/Space; Escape dismisses them.
- A selected place moves the map. Attribution remains visible.
- Open Ver reporte completo from the list and a popup, and open a UUID deep link.
- Report photo, Guatemala date, both states, checks and location map are visible.
- Back/forward and Volver al mapa retain map position, filters and selection.
- Panel de reportes shows category/status/resolution bars and numeric counts.
- Descargar CSV sends the same bbox and filters as the stats request, no limit.
- Try a missing UUID and unknown route, then recover using retry/back.
- On slow connections navigate away during detail/stats/search loading: no stale UI.
- Stub verification is visibly distinguished from real verification.
- Tab through filters/list/markers; Escape closes a popup and restores focus.
- Pan quickly and change filters; only the latest area's results remain.
- Check loading, empty and API-offline states, then retry after recovery.
- Disable tile requests: the report list should remain usable.
- Enable reduced motion: selecting a report should avoid animated flight.

Stop the server with Ctrl+C when the review is complete.
STEPS
npm run dev -- --host 127.0.0.1
