# What the app and the Dashboard must keep consistent

Phase 1 UX spec, 2026-11-21. "Dashboard" here means the web `portal/` (map workspace, report page, triage and the
statistics dashboard). The binding wire contract is `documentation/api-contract.md`; this file lists what users see in
both products, so that a citizen who opens a shared link, or a municipal officer who talks to a citizen, sees the same thing.

Each row says where it lives today and whether the two sides already match.

## 1. Data models

### Report (contract v0.1–v0.5)

| Field | Meaning | App | Portal | Match |
|---|---|---|---|---|
| `id` (uuid) | Report reference shown to people | "Referencia: <id>" (full uuid) | id in the report page | ⚠️ both show long uuids; agree a short display form? |
| `category` | Stable category id | `core/categories.dart` | `src/categories.js` | ✅ same six ids and labels |
| `latitude`, `longitude` | Point of the problem | Cards show coordinates | Map + report page | ✅ (no address field on either side) |
| `captured_at`, `created_at` | Photo time, server time (UTC) | `formattedDate()` es-GT | relative "hace 3 días" + exact Guatemala time in `title` | ⚠️ app uses absolute dates, portal relative |
| `status` | Verifier verdict `pending/verified/rejected` | Status chips | Verifier filter, pins | ✅ |
| `state`, `state_group` | Municipality handling state (11 states, 6 groups) | `core/citizen_states.dart` | `src/states.js`, `i18n.js` | ❌ different words (open-decisions #13) |
| `resolution` | Legacy v0.1 handling | fallback only | fallback only | ❌ `closed` maps differently (open-decisions #14) |
| `note` | Citizen description (≤280) | Wizard step, cards, detail | List rows (2 lines), report page | ✅ |
| `public_note` | Last official message | "Mensaje del municipio" | Staff writes it on transitions | ✅ |
| `events[]` | Public timeline `{at, actor_role, from_state, to_state, public_note}` | "Historial" | History rail | ✅ (internal notes never in the app) |
| `duplicate_of` | Main report when closed as duplicate | "Ver el reporte principal" | Staff sets it | ✅ |
| `verification` `{passed, mode, checks[]}` | Verifier result | Result + "Verificación" with reason/fix per check name | Explanation + checks | ⚠️ app keys reasons on `name`, ignores `code`; app labels only `mode: stub` (open-decisions #15) |
| `photo_url`, `thumbnail_url` | Full photo, 320 px thumbnail | Detail uses photo; cards use photo | List uses thumbnail | ⚠️ app cards could use `thumbnail_url` (less data) |
| `citizen_alias` | Optional public display name | Not parsed or shown | **Assumption:** not shown either (not checked) | ❓ who shows it, where? |
| `assignee`, `verified_at`, `resolved_at`, `closed_at`, `state_changed_at` | Staff/timing fields | Parsed, mostly unused | Used in triage and stats | ✅ |

Privacy invariants both sides keep: no phone number, phone hash, citizen id or device id is ever shown or exported;
photos are public; EXIF is stripped by the API.

### States and groups

One table, two vocabularies today. Group → color mapping is the same on both sides (from `design-tokens.md`):

| Group | States | Color role |
|---|---|---|
| `pending` | `pendiente_verificacion` | hollow / outlined dot |
| `open` | `nuevo`, `en_revision` | open (orange today) |
| `in_work` | `programado`, `en_proceso` | in work (green today) |
| `resolved` | `resuelto` | resolved (blue today) |
| `closed` | `rechazado_verificador`, `no_procede`, `fuera_de_competencia`, `duplicado` | closed (gray); rejected uses error red on portal pins |
| `hidden` | `oculto` | not shown publicly |

Rule on both sides: **never color alone**; the state word sits next to the dot in the normal text color.

### Categories

Six stable ids (`accessibility`, `sidewalk`, `pothole`, `graffiti`, `open_drain`, `street_light`), three groups
(`movilidad`, `espacio_publico`, `servicios`), SLA hours per category in the API. A change touches three files in the same
change (API, app, portal). Icons differ: the app uses Material icons, the portal draws its own SVG paths. **A shared icon
set is a Phase 2 design-system item.**

### Statistics (`GET /api/stats`)

| Number | App use | Dashboard use | Note |
|---|---|---|---|
| `resueltos` | Big counter on Inicio | Headline counter | Both use the API default window (last 90 days) unless the portal asks `include_old=true`. The two numbers can differ on the same day — label the period on both. |
| `recibidos`, `abiertos`, `cerrados_sin_solucion`, `tasa_resolucion` (0–1), `sla_cumplido` (0–1), `vencidos` | — | Dashboard | Ratios are 0–1 on the wire; show `%` and "Sin datos" for null. |
| `weekly[]`, `por_categoria[]`, `top_categorias[]`, `resolucion_horas` | — | Charts with **Ver tabla** | If the citizen home gets metric cards, reuse the same definitions and wording. |

No zone/municipality field exists, so neither side can show "per zone" numbers.

### Map

Same endpoint and semantics: `GET /api/reports/clusters` (clusters below zoom 15, single reports from 15), cluster
bubbles in the primary color with a count, single pins in the state color with a white outline and a state letter,
pending pins outlined. OSM tiles and attribution on both sides.

## 2. Components that must look and read the same

| Component | App | Portal | To align |
|---|---|---|---|
| Status dot + word | `StatusDot`, `StatusLabel`, `StatusChips` | `.state-dot` + label | Same colors per group, same words (decision #13), same order |
| Map pin (state letter) | `StatusMapPin` | singleton pins | Same letters per state, same sizes relative to touch/click targets |
| Cluster bubble | `NeutralMapPin` | cluster markers | Same color and count format (`1.234`, es-GT grouping) |
| Category icon | Material icons | custom SVG | One shared icon set |
| Report card / row | Large photo card | Row with 72×72 thumbnail | Same field order: category · state · place · note · date · reference |
| Verifier explanation | Reason + fix per check | Explanation text | Same sentences for the same `code` |
| Timeline | "Historial" list | History rail | Same event wording and public-note label ("Mensaje del municipio") |
| Empty / error states | `EmptyState`, `FriendlyErrorView` | portal empty/error blocks | Same tone; never technical messages |
| Numbers and dates | `humanizedCount()`, `formattedDate()` | `Intl` es-GT | Same locale (es-GT), same timezone (America/Guatemala), same relative/absolute rule |
| Public link | `PUBLIC_PORTAL_URL/#/reports/<id>` | hash route `#/reports/<id>` | Keep the route stable; shared links land on the portal page |

## 3. Design tokens

`documentation/design-tokens.md` says app and portal share the same values (`app/lib/core/theme.dart`,
`portal/src/styles/tokens.css`). Today they match: `bar #3A3F44`, `primary #0F7A99`, `primary-dark #0B6079`, accent
`#E8731A`, page `#F3F4F6`, surface `#FFFFFF`, border `#D9DEE3`, text `#1F2933`, muted `#52606D`, status colors. The new
direction in [design-direction.md](design-direction.md) changes these for **both** products unless the team decides
otherwise (open-decisions #20). Portal dark mode is not implemented; the app has one.

## 4. Process proposal

**Assumption:** the team wants one source of truth. Proposal: after Isa's review, move this file to `documentation/`
and treat it like the API contract, so that any change to a shared item updates the app, the portal and this file in the
same pull request.
