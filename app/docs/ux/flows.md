# User flows (citizen app)

Phase 1 UX spec, 2026-11-21. Derived from the code in `app/lib/` (branch `feat/app-simpler-report-flow`, commit `1640dd6`)
and from `app/README.md`, `documentation/ui/app-ui-notes.md`, `documentation/ui/app-reference-seeclickfix.md`,
`documentation/mvp-plan.md`, `documentation/api-contract.md` and `documentation/decisions/`. No Notion export was available
(`docs/notion-export/` does not exist), so Notion content is not reflected here.

Status labels: **implemented** = works end to end in code (maybe only against a dev API), **partial** = some steps exist or
behavior is a local stand-in, **missing** = documented or implied but not in code. Text marked **Assumption** is not stated
in code or docs.

## The app today, in short

Aldia is a Flutter app (Android, iOS, Linux demo), not a native Android/Jetpack Compose app. All UI text is Spanish
(Guatemala) in `lib/core/strings.dart` and inline in widgets. A citizen:

1. sees three onboarding slides on first run,
2. must sign in with a Guatemalan phone number and a six-digit code (or a local **test account** in the MVP build),
3. lands on a five-tab shell: **Inicio**, **Avisos**, **Reportar** (center plus), **Mis reportes**, **Perfil**,
4. reports a problem in a five-step wizard: **Ubicación → Categoría → Foto → Detalles → Revisar y enviar**, then sees
   a result screen with the photo verifier's verdict,
5. explores public reports on a map or a list (Inicio → **Explorar mi ciudad**), filters them, opens a detail page with a
   timeline, follows reports (heart) and shares them,
6. gets **Avisos**: a local inbox of state changes that the app notices when it refreshes the citizen's reports (no push).

Drafts autosave, an outbox resends when the network returns, and every report has one idempotency key so retries never
duplicate it. Real SMS delivery, push notifications, rewards, account deletion and real manual review do not exist.

## Target changes decided on 2026-11-21

From [`documentation/decisions/ux-2026-11-21.md`](../../../documentation/decisions/ux-2026-11-21.md). The flows below
still describe today's code; Phase 2 wireframes use these targets:

- **F2:** sign-in moves from app start to the **Revisar y enviar** step (citizens browse and fill in the report freely).
  Phone code stays; leave room for a future citizen ID (DPI) method.
- **F9:** after **Categoría**, a "¿Es este tu reporte?" step appears only when the nearby endpoint finds matches.
- State names: citizen wording in the app and the public portal; official wording only in staff screens.

## Flow index

| # | Flow | Status |
|---|---|---|
| F1 | First run onboarding | implemented |
| F2 | Sign in with phone code | partial (no real SMS; development console code only) |
| F3 | Enter with the MVP test account | implemented (temporary) |
| F4 | Report a problem (wizard) | implemented |
| F5 | Correct a report the verifier rejected | implemented |
| F6 | Send for manual review after repeated rejections | partial (saves locally only) |
| F7 | Report while offline (outbox) | implemented |
| F8 | Resume an unfinished draft | implemented |
| F9 | Avoid a duplicate before sending | partial (only after sending) |
| F10 | Explore reports on the map | implemented |
| F11 | Explore reports in the list, search and filter | implemented |
| F12 | View a report's detail and history | implemented |
| F13 | Follow a report | implemented (device-local) |
| F14 | Share a report | implemented |
| F15 | Receive notices about my reports | partial (local inbox, no push) |
| F16 | Review my reports, drafts and outbox | implemented |
| F17 | Manage profile, sign out, delete local data | partial (no alias edit, no account deletion) |
| F18 | See what is new after an update | implemented |
| F19 | Give consent / read privacy text before the first report | missing |
| F20 | Earn rewards for reports | missing (decision pending) |

## Flows

### F1. First run onboarding — implemented

*As a first-time citizen, I want a short introduction so that I know what Aldia does and what is public.*

1. App starts; `onboarding_seen` is false → `OnboardingScreen`.
2. Three slides: "Reporta lo que ves en tu calle", "La foto se toma en el momento", "Tu privacidad".
3. **Omitir** at any time, or **Siguiente** → **Empezar** on the last slide.
4. Flag saved; next step is F2/F3 (login is required by default) or the shell if login is off.

Code: `features/onboarding/onboarding_screen.dart`, `main.dart`.

### F2. Sign in with phone code — partial

*As a citizen, I want to sign in with my phone number so that my reports are linked to me and I can follow them on any
device.*

1. After onboarding, if `REQUIRE_CITIZEN_LOGIN=true` (app default) and no account → **Entra a Aldia** screen.
2. Enter eight digits after the fixed `+502` prefix → **Solicitar código**.
3. API always answers 202. Code field, optional display name and **Mostrar mi nombre en reportes nuevos** switch appear.
4. Enter the six-digit code → **Verificar número**. **Reenviar código** unlocks after 60 s; **Cambiar número** goes back.
5. On success the shell (Inicio) appears. Session lasts 90 days on this installation.

Gaps: no SMS/WhatsApp provider; the code only appears in the dev API log. Only Guatemala numbers in the UI although the
verifier accepts GT/CO/MX places. The login decision says the code is asked "at the final report step", but the code asks
at app start (see open decisions). The non-standalone variant (`showCitizenLogin` from Perfil) still exists.

Code: `features/citizen/login_sheet.dart`, `services/citizen_auth_service.dart`.

### F3. Enter with the MVP test account — implemented (temporary)

*As a tester or demo viewer, I want to enter without a phone code so that I can try the app before login is final.*

1. On **Entra a Aldia**, tap **Entrar con cuenta de prueba** (visible unless built with `ALLOW_TEST_ACCOUNT=false`).
2. A local flag is set; the shell appears. Perfil shows "Cuenta de prueba".
3. Reports are sent without credentials, so the API must keep `REQUIRE_CITIZEN_LOGIN=false`.

Code: `services/test_account.dart`, `app.dart`.

### F4. Report a problem — implemented

*As a citizen, I want to report a street problem with a live photo and its location so that the municipality can fix it.*

Entry: center **Reportar** tab, **Reportar un problema** on Inicio, or **Hacer mi primer reporte** on an empty Mis reportes.
The wizard opens as a full-screen sheet titled **Reportar**, with a help icon ("Tu reporte, paso a paso"), a close icon,
"Paso N de 5" and a summary row (camera icon, place, category) on each step.

1. **Ubicación.** GPS starts automatically. The citizen can search an address (explicit **Buscar**, Nominatim), tap the
   map to move the pin, use **Usar mi ubicación**, or type latitude/longitude. Warnings: permission denied/forever,
   GPS off, no signal, accuracy > 50 m. Bottom button **CONFIRMAR UBICACIÓN**.
2. **Categoría.** Search field plus grouped list (Movilidad, Espacio público, Servicios) from `GET /api/categories`,
   with built-in fallback when offline. **Siguiente**.
3. **Foto.** Live camera only (no gallery, no skip). Preview, **Tomar otra foto**, bottom button **Usar esta foto**.
4. **Detalles.** Optional description, max 280 characters, example hint.
5. **Revisar y enviar.** Photo, place, category, note, each with **Editar: …**; estimated upload size; notice that the
   photo and the point are public. **Enviar reporte**.
6. **Resultado.** One of: verified ("Reporte verificado"), rejected (F5), pending verification, queued (F7), duplicate
   (F9). Shows the reference id and **Cerrar**.

Exit: back to the shell; Mis reportes and Inicio refresh.
Code: `features/report/report_flow_screen.dart`, `report_flow_controller.dart`.

### F5. Correct a rejected report — implemented

*As a citizen whose photo did not pass the checks, I want to know why and fix it so that my report is accepted.*

1. Result shows "La foto no pasó la verificación" and the failed checks with a reason and a fix per check (place,
   freshness, duplicate, category, image).
2. Actions: **Tomar otra foto**, **Cambiar categoría**, **Ajustar ubicación**.
3. Editing starts a new attempt with a new idempotency key; the draft and failure count are kept.

### F6. Send for manual review — partial

*As a citizen whose photo was rejected several times, I want a person to review it so that I am not stuck.*

1. After three failed attempts, **Enviar para revisión manual** appears.
2. Tapping it only saves the draft locally and says "La revisión manual aún no está disponible." Nothing reaches the
   server or the portal.

### F7. Report while offline — implemented

*As a citizen with a weak connection, I want my report saved and sent later so that I do not lose it.*

1. **Enviar reporte** puts the report in a durable outbox (JSON + photo in app storage).
2. With no network the result says **Esperando red** and explains automatic sending.
3. The outbox retries when connectivity returns and when the app resumes. Mis reportes → **Por enviar** shows the item
   with **Reenviar ahora** and **Eliminar**.
Known limit: queued items use the account active when they are finally sent (README "provisional outbox behavior").

### F8. Resume a draft — implemented

*As a citizen who was interrupted, I want to continue my unfinished report so that I do not start over.*

1. Every change autosaves a draft. Inicio/Explorar show a **Continuar borrador** banner ("Tienes un reporte sin
   terminar", age).
2. Mis reportes → **Borradores** lists drafts with **Continuar borrador** / **Eliminar borrador**.
3. Restoring returns to the saved step, or to the first missing prerequisite (for example a lost photo file).

### F9. Avoid a duplicate before sending — partial

*As a citizen, I want to see if someone already reported this problem so that I can follow it instead of sending a copy.*

- Implemented: when the API's `duplicate` check rejects the report, the result shows the existing report with
  **Seguir este reporte** (no new upload).
- Missing: a nearby step **before** the photo. It was built (reference task 4) and then removed (README; draft
  restore maps the old `duplicates` step to `photo`). `ApiClient.nearbyReports` and `GET /api/reports/nearby` still exist.
  `documentation/ui/app-ui-notes.md` still lists the step.

### F10. Explore the map — implemented

*As a citizen, I want to see reported problems around me on a map so that I know what is already known.*

1. Inicio → **Explorar mi ciudad** → dark bar with search, locate, filter (with count badge) and overflow menu
   (**Actualizar**, **Quitar filtros**); tabs **MAPA** / **LISTA**.
2. Map shows clusters (zoom to expand) or state-colored pins with a state letter. Tap a pin → summary sheet → **Ver
   detalle**. Layers button hides the report overlay. If clustering fails, single pins with a notice.

### F11. Explore the list, search and filter — implemented

1. **LISTA** shows large photo cards: status dot + word, category, coordinates, note, date, reference, heart, share.
2. Search (top bar) filters the loaded list by category, state word and note.
3. Filter sheet: **Estado** and **Categoría** dropdowns, **Aplicar**, **Quitar filtros**.

### F12. View a report's detail and history — implemented

*As a citizen, I want to see a report's photo, state and history so that I know what the municipality did.*

1. From a card, pin sheet, notice or Mis reportes → **Detalle del reporte**.
2. Shows: category heading, photo, status chips, state explanation, reference, date, note, **Mensaje del municipio**,
   duplicate link (**Ver el reporte principal**), **Historial** timeline, nearby similar reports, **Verificación** checks.

### F13. Follow a report — implemented (device-local)

1. Heart on a card or **Seguir este reporte** on a duplicate result.
2. Followed reports appear in Mis reportes and feed Avisos. Follows live only on this device (not on the account).

### F14. Share a report — implemented

1. Share icon on a card → native share sheet (WhatsApp if installed); Linux opens WhatsApp web; fallback copies a link.
2. Link is `PUBLIC_PORTAL_URL/#/reports/<id>`.

### F15. Receive notices about my reports — partial

*As a citizen, I want to be told when my report changes state so that I do not have to check.*

1. Avisos explains that changes are detected when the app refreshes; **Actualizar avisos**.
2. New state for an own or followed report → notice (category, state, date, reference); tap → detail.
3. Missing: push notifications, background polling, read/unread state.

### F16. Review my reports — implemented

1. Mis reportes sections: **Por enviar** (outbox), **Borradores**, **Enviados y seguidos** (account reports merged with
   device-local ids and follows).
2. Empty state: "Aún no tienes reportes…" with **Hacer mi primer reporte**.

### F17. Manage profile — partial

1. Perfil: masked phone (or "Cuenta de prueba"), **Cerrar sesión** or **Verificar mi número**, **Nombre público** (info
   only), **Idioma** (fixed Spanish), **Versión de Aldia**, **Borrar mis datos** (confirm dialog; local data only).
2. Missing: edit display name or its visibility after sign-in, delete the server account, change language.

### F18. What is new after an update — implemented

On the first open after a version change, a **Novedades de Aldia** dialog lists changes; **Entendido** closes it.

### F19. Consent and privacy before the first report — missing

Listed in `documentation/mvp-plan.md` (pitch-readiness item 4: "privacy text and consent screen before the first
report"). Today only the onboarding slide "Tu privacidad" and the public-photo notice on the review step exist.

### F20. Rewards — missing

`documentation/decisions/2026-11-19.md`: rewards (tax or bill discounts) are "to be defined", after the government PoC.
No code. Do not design it until the team decides.
