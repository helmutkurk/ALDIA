# Screens (citizen app)

Phase 1 UX spec, 2026-11-21. One row per screen or sheet in `app/lib/` today. Flow ids refer to [flows.md](flows.md).

**States** columns: ✅ handled in code, ⚠️ partly handled (see note), ❌ missing, — not applicable.
"Success" means the screen's normal content state.

## Screen inventory

| # | Screen (code) | Purpose | Key components | Entry → exit | Empty | Loading | Error | Success |
|---|---|---|---|---|---|---|---|---|
| S1 | Onboarding (`OnboardingScreen`) | Explain Aldia, live photo rule, privacy | 3 slides, page indicator, **Omitir**, **Siguiente/Empezar** | First run → S2 or S3 | — | — | — | ✅ |
| S2 | Entra a Aldia (`CitizenLoginScreen` / `CitizenLoginSheet`) | Sign in with phone + 6-digit code | `+502` phone field, code field, display name, public-name switch, **Solicitar código**, **Verificar número**, resend timer, **Cambiar número**, **Entrar con cuenta de prueba** | After S1 or sign-out → S3. Sheet variant from S17 → back to S17 | — | ✅ linear bar, inputs disabled | ✅ inline text (live region) | ⚠️ no confirmation; jumps straight to S3 |
| S3 | Shell (`HomeScreen`) | Top-level navigation | Top bar, `NavigationBar`: Inicio, Avisos, (+) Reportar, Mis reportes, Perfil; reselect scrolls to top; draft banner | After S2 → any tab; (+) opens S8 | — | — | — | ✅ |
| S4 | Inicio (`_Landing`) | Show impact and the two main actions | Dark `bar` background, city icon, "Tu ciudad, al día", big resolved count, **Explorar mi ciudad**, **Reportar un problema** | Tab → S5 or S8 | — | ⚠️ shows "—" + "dato no disponible" while loading (same as error) | ⚠️ "—" + "Reportes resueltos: dato no disponible", no retry | ✅ |
| S5 | Explorar · MAPA (`_MapView`) | See reports geographically | Search, locate, filter badge, overflow menu, MAPA/LISTA tabs, clusters, state pins, layers button, zoom, OSM attribution | S4 → S6 (tab), S5a (pin) | ❌ no message when the viewport has no reports | ❌ no indicator while pins load | ⚠️ cluster failure → notice + single pins; total failure → silently empty map | ✅ |
| S5a | Pin summary sheet | Preview one report | Category, state, **Ver detalle** | S5 pin → S13 | — | — | ⚠️ snackbar "No se pudieron cargar los reportes." | ✅ |
| S6 | Explorar · LISTA (`_ReportList`, `ReportTile`) | Browse and search reports | Large photo cards: dot + state word, category, coordinates, note, date, reference, heart, share | S4/S5 → S13 | ✅ "Todavía no hay reportes en esta zona." / filtered empty with **Quitar filtros** / search empty | ✅ spinner | ✅ EmptyState + **Reintentar** | ✅ |
| S7 | Filtros (`_FiltersSheet`) | Narrow map/list | **Estado** and **Categoría** dropdowns, **Aplicar**, **Quitar filtros** | S5/S6 filter icon → back | — | — | — | ✅ |
| S8 | Wizard · Ubicación (`_LocationStep`) | Set where the problem is | Summary row, "Paso 1 de 5", address search + results, map with pin, **Usar mi ubicación**, lat/lon inputs, accuracy text, **CONFIRMAR UBICACIÓN** | (+), S4, S16 empty, draft banner → S9; close → back | ✅ no-results text from geocoder (not verified in detail) | ✅ "Buscando ubicación…" | ✅ denied / denied forever (+ **Abrir ajustes**) / GPS off / no signal / >50 m / invalid coordinates | ✅ |
| S9 | Wizard · Categoría (`_CategoryStep`) | Choose problem type | Search field, group headers, 64 dp selectable rows with icon and check | S8 → S10 | ✅ "No encontramos esa categoría…" | ⚠️ silent; offline fallback list | ⚠️ silent fallback to built-in list | ✅ |
| S10 | Wizard · Foto (`_PhotoStep`) | Take the live photo | Circular camera target, rule text, preview, **Tomar foto / Tomar otra foto**, **Usar esta foto** | S9 → S11 | ✅ no photo yet | ❌ no indicator while the camera opens | ✅ camera error; missing stored photo | ✅ preview |
| S11 | Wizard · Detalles (`_NoteStep`) | Optional description | Photo thumbnail, text field (280), hint | S10 → S12 | ✅ optional | — | — | ✅ |
| S12 | Wizard · Revisar y enviar (`_ReviewStep`) | Confirm before sending | Photo, place, category, note, **Editar: …** links, upload size, public-photo notice, **Enviar reporte** | S11 → S14 | — | ✅ "Enviando…" | ✅ "No se pudo enviar…"; storage error | ✅ |
| S13 | Detalle del reporte (`ReportDetailScreen`) | Full report and history | Category heading, photo (fade, broken-image fallback), status chips, explanation, reference, date, note, **Mensaje del municipio**, duplicate hint, **Historial**, nearby similar reports, **Verificación** checks | S5a, S6, S15, S16, S14 → back; nearby → S13 | ⚠️ empty timeline shows the state explanation | ⚠️ shows the passed-in report while refreshing; no indicator | ⚠️ **Reintentar** for the refresh; nearby failure is silent | ✅ |
| S14 | Resultado (`_ResultView`, `_DuplicateResult`) | Tell the outcome of sending | Title by state (verified / rejected / pending / **Esperando red** / **Borrador** / followed), photo, reference, checks with reason + fix, **Tomar otra foto**, **Cambiar categoría**, **Ajustar ubicación**, **Enviar para revisión manual**, duplicate card + **Seguir este reporte**, **Cerrar** | S12 → shell, or back into S8–S10 to correct | — | — (S12 handles it) | ✅ rejected variant | ✅ |
| S15 | Avisos (`NoticesScreen`) | Local inbox of state changes | Explanation text, **Actualizar avisos**, notice rows (category, state, date, reference) | Tab → S13 | ✅ icon + text | ✅ linear bar | ✅ "No se pudo actualizar. Los avisos guardados siguen disponibles." | ✅ (no unread marker) |
| S16 | Mis reportes (`MyReportsScreen`) | My outbox, drafts, sent and followed reports | Sections **Por enviar**, **Borradores**, **Enviados y seguidos**; card actions **Reenviar ahora**, **Eliminar**, **Continuar borrador**, **Eliminar borrador**; delete confirm dialogs | Tab → S13, S8 | ✅ with **Hacer mi primer reporte** | ✅ spinner in the sent section | ✅ sent section only, with **Reintentar** | ✅ |
| S17 | Perfil (`ProfileScreen`) | Account and local data | Avatar, "Tu perfil en Aldia", phone (masked / "Cuenta de prueba" / unverified), **Cerrar sesión** or **Verificar mi número**, **Nombre público** (info only), **Idioma**, **Versión de Aldia**, **Borrar mis datos** | Tab → S2 sheet, S17a | — | ⚠️ linear bar for delete; sign-out only disables the button | ✅ snackbars for delete/sign-out errors | ✅ |
| S17a | Borrar datos dialog | Confirm local deletion | Title, explanation, **Cancelar**, **Borrar datos locales** | S17 → S17 | — | — | — | ✅ |
| S18 | Novedades dialog (`changelog.dart`) | What changed in this version | Bullet list, **Entendido** | First open after update → S3 | — | — | — (fails silently by design) | ✅ |
| S19 | Wizard help dialog | Explain the steps | "Tu reporte, paso a paso", **Cerrar** | Help icon on S8–S12 | — | — | — | ✅ |
| S20 | Friendly error view (`FriendlyErrorView`) | Replace Flutter's red error widget | Calm message instead of a crash dump | Any build error | — | — | ✅ | — |

## Missing states to design (summary)

1. **Inicio counter:** separate loading (skeleton) from "not available", and add a retry or pull-to-refresh.
2. **Map:** loading indicator; empty viewport message ("No hay reportes en esta zona. Aleja el mapa."); error state
   with retry when both clusters and the plain list fail.
3. **Detail:** visible refresh indicator; nearby-reports failure (silent today is acceptable if the team agrees).
4. **Camera opening:** loading feedback between tap and camera.
5. **Category step:** a visible hint when the offline fallback list is in use.
6. **Login success:** a short confirmation (or a first-time tip on Inicio) after verification.
7. **Avisos:** unread vs read; count badge on the tab (needs a decision, see open-decisions).
8. **Perfil sign-out:** progress indicator.

## Target design (Phase 2 wireframes, 2026-11-21)

The approved low-fi wireframes are in the Figma file "Aldia - prueba MCP", page "Wireframes low-fi", as a clickable
prototype with three flows (1 · Primer uso y reporte, 2 · Explorar, 3 · Seguimiento). They follow
[`documentation/decisions/ux-2026-11-21.md`](../../../documentation/decisions/ux-2026-11-21.md). Frame names map to
the screens above:

| Frames | Screen | What changes vs. today |
|---|---|---|
| A1 | S1 Onboarding | Ends on Inicio; no login screen after it |
| A2, A2b | S4 Inicio | Light surface, metric card with period and sparkline; separate loading/unavailable state |
| A3, A4, A5, A5b | S5 Explorar · Mapa | Full-screen map with floating controls, category-icon pins, legend; new loading, empty and error states |
| A3b | S7 Filtros | Bottom sheet over the map: search, category chips, state chips, Aplicar / Quitar filtros |
| A6, A7, A7b, A7c | S6 Explorar · Lista | Same header as the map (back, Mapa/Lista, filters); skeleton loading |
| A8 | S13 Detalle | Same content; technical-verification note |
| B1–B6b | S8–S12 Wizard | Category icon grid; conditional "¿Es este tu reporte?" step; sending state |
| B7, B8, B8b | S2 (sheet) | Phone sign-in moves to the send step, as a sheet over the review |
| B9, B10, B11 | S14 Resultado | Same outcomes, clearer layout; technical-verification note |
| C1–C4 | S15, S16 | Unread dot on notices (proposal, #16) |
| C5, C6, C7 | S17, S17a | New "sin cuenta" variant, since sign-in is no longer required at start |

## Screens that do not exist yet

| Screen | Source | Status |
|---|---|---|
| Consent / privacy before first report | `documentation/mvp-plan.md` pitch item 4 | missing |
| Nearby / "Is this your request?" step | reference task 4; removed from code | missing (decision needed) |
| Edit display name / visibility | `documentation/decisions/citizen-login.md` (not implemented) | missing |
| Delete my account | same decision | missing |
| Push permission prompt | README, decisions: push not built | missing |
| Rewards | `documentation/decisions/2026-11-19.md` | missing, undecided |

**Assumption:** the empty-state copy proposed above is a placeholder for the team to review; it is not in the code.
