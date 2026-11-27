# AlDía glossary

The shared language of the app, the portal, the API and the verifier. Use these words in code, docs, commits and
conversations. Each term gives the English word (code and docs), the contract identifier in backticks where one exists,
and the Spanish word the user sees. When two words exist for one idea, use the first one and avoid the others.

Folder glossaries add detail for one area: [app](app/GLOSSARY.md) (Explorar). If a folder glossary and this file
disagree, this file wins and the folder glossary is fixed.

## Product and people

**AlDía**:
The product: citizens send verified photo reports of street problems, and municipalities see and handle them.
Written "AlDía" in all user-facing text; "Aldia" or `aldia` only in code, folder and package names.
_Avoid_: Ciudad Check, CiudadCheck (old names)

**Citizen** (`citizen`, UI *ciudadano*):
A person who uses the app to send or follow reports. A citizen may be anonymous or signed in with a phone code.
_Avoid_: user (ambiguous with staff), worker, reporter, client

**Municipality** (UI *municipio*):
The local government that receives reports and handles them. It is the customer of the portal.
_Avoid_: city, government (use only for the national level or the pitch), client, entity

**Staff** (`staff`, UI *personal*):
Municipality employees who sign in to the portal to handle reports. Every staff member has one role.
_Avoid_: admin (that is one role), operator (that is one role), user, official

**Role** (`role`):
What a staff member may do: **operator**, **supervisor** or **admin**. The system itself acts with the role `system`.

**Operator** (`operator`, UI *operador*):
Staff role for daily triage and handling of reports.

**Supervisor** (`supervisor`):
Staff role that may also override verifier rejections, reopen closed reports and hide reports.

**Admin** (`admin`):
Staff role with all supervisor rights that also manages staff accounts.

**Other entity** (UI *otra entidad*, *otra institución*):
An institution that is not the municipality and is responsible for a problem (for example a utility company).

## Reports

**Report** (`report`, UI *reporte*):
One street problem sent by a citizen: one photo, one point, one category, an optional note. It is the core object of
AlDía.
_Avoid_: case, ticket, issue, incident, request, complaint, denuncia

**Category** (`category`, UI *categoría*):
The kind of street problem. The list is fixed: `accessibility`, `sidewalk`, `pothole`, `graffiti`, `open_drain`,
`street_light`. Ids are stable; only the Spanish labels may change.
_Avoid_: type, service (Open311 word only)

**Category group** (`group`):
A heading that bundles categories in the app and the portal: **Movilidad**, **Espacio público**, **Servicios**.

**Note** (`note`, UI *descripción* / *detalles*):
The citizen's optional text about the problem, at most 280 characters.
_Avoid_: comment, description (in code)

**Capture time** (`captured_at`):
When the citizen took the photo. Different from **created at**, when the API stored the report.

**Point** (`latitude`, `longitude`, UI *ubicación*):
The place of the problem that the citizen confirmed. It is public, like the photo.
_Avoid_: address (an address is only a search help), position, GPS

**Reference** (UI *Referencia*):
The report id as the citizen sees it, to quote it to the municipality.

**SLA** (`sla_hours`):
The target time, per category, in which the municipality should resolve a report.

**Overdue** (`vencidos`, UI *vencido*):
An open report older than the SLA of its category.

## Verification

**Verifier** (UI *verificador*):
The internal service that checks each photo before the report is accepted. It checks usability and consistency, not
truth: a passed report is not proof of a real problem.
_Avoid_: validator, AI, model (the model does not exist yet)

**Check** (`check`):
One named test of the verifier or the API, with a pass or fail and a reason (`image`, `place`, `freshness`,
`sharpness`, `exposure`, `exif_time`, `exif_gps`, `screen_photo`, `category`, `duplicate`).

**Hard check**:
A check that rejects the report when it fails. All checks are hard except `screen_photo`.

**Soft check**:
A check that only gives a hint and never rejects. Today only `screen_photo`.

**Verification status** (`status`):
The verifier's verdict on a report: `pending` (no answer yet), `verified` or `rejected`. It never changes after the
answer, except by a supervisor override.
_Avoid_: state (that is the case state)

**Verified**:
A report whose verification status is `verified`. Only use it for photos, never for phone numbers (see **Phone
verification**).

**Verifier rejection** (`rechazado_verificador`, UI *Falta ajustar la foto*):
A report whose photo failed a hard check. The citizen can fix it and send it again.
_Avoid_: rejected report (ambiguous with a staff closure)

**Override**:
A supervisor's decision that moves a verifier rejection to `nuevo`, with an internal note.

**Duplicate check** (`duplicate`):
The API's check that rejects a new photo that is almost the same as a report of the same category close by.

**Nearby reports** (UI *¿Es este tu reporte?*):
Open reports of the same category near a point, shown to the citizen before sending, so they can follow one instead of
sending a copy.

**Manual review** (UI *revisión manual*):
A future path in which a person checks a photo that the verifier rejected many times. Not built yet.

## Case handling

**Case state** (`state`, UI *estado*):
Where a report is in the municipality's handling, one of eleven values:
`pendiente_verificacion`, `rechazado_verificador`, `nuevo`, `en_revision`, `programado`, `en_proceso`, `resuelto`,
`no_procede`, `fuera_de_competencia`, `duplicado`, `oculto`.
_Avoid_: status (that is the verification status), resolution, stage

**State group** (`state_group`):
The public bucket of a case state: `pending`, `open`, `in_work`, `resolved`, `closed`, `hidden`. Map colors, legends
and filters use state groups.

**Resolution** (`resolution`):
A legacy summary of the case state (`open`, `acknowledged`, `fixed`, `closed`), kept only for old clients and Open311.
Do not use it in new work.

**Transition** (`transition`):
One legal change from one case state to another, done by the system or by staff. Illegal transitions are refused.

**Event** (`event`, UI *Historial*):
The record of one transition: when, who, from which state, to which state, and the public note. The list of events is
the report's **timeline**.
_Avoid_: log, activity, history (in code)

**Actor** (`actor`, `actor_role`):
Who did a transition: a staff username or `system`.

**Public note** (`public_note`, UI *Mensaje del municipio*):
A message from staff to citizens, shown on the report.

**Internal note** (`internal_note`):
A message only staff can read.

**Assignee** (`assignee`):
The staff member responsible for a report now.

**Duplicate** (`duplicado`, `duplicate_of`, UI *Ya estaba reportado*):
A case state set by staff: the report describes the same problem as another report, the **main report**.
_Avoid_: using "duplicate" alone; say **duplicate check** or **duplicate (state)**

**Reopen**:
A supervisor's transition from a resolved or closed report back to `en_revision`.

**Hide** (`oculto`, UI *No disponible*):
A supervisor's moderation that removes a report from public views. Unhide restores the previous state.

### Two vocabularies for one state

Citizens and public pages use the **citizen wording**; staff screens use the **official wording**
([UX decision 4](documentation/decisions/ux-2026-11-21.md)).

| State | Citizen wording | Official wording |
|---|---|---|
| `pendiente_verificacion` | En verificación | Pendiente de verificación |
| `rechazado_verificador` | Falta ajustar la foto | Rechazado por verificador |
| `nuevo` | Recibido | Nuevo |
| `en_revision` | En revisión | En revisión |
| `programado` | Programado | Programado |
| `en_proceso` | En proceso | En proceso |
| `resuelto` | Resuelto | Resuelto |
| `no_procede` | Cerrado | No procede |
| `fuera_de_competencia` | Corresponde a otra entidad | Fuera de competencia |
| `duplicado` | Ya estaba reportado | Duplicado |
| `oculto` | No disponible | Oculto |

State group words in legends and filters: En verificación, Abierto, En proceso, Resuelto, Cerrado.

## Citizen account

**Phone code login** (UI *Entra a AlDía*, *Solicitar código*):
How a citizen signs in: a phone number and a six-digit one-time code.
_Avoid_: register, sign up, SMS login

**Phone verification** (`otp`, UI *Verificar número*):
Proving that the citizen owns the phone number. Not related to photo verification.

**Device** (`device_id`):
One installation of the app. A citizen session belongs to one device.

**Citizen session**:
The proof that a citizen is signed in on one device. It lasts 90 days.

**Alias** (`alias`, UI *Nombre público*):
An optional display name. Private unless the citizen chooses to show it on new reports.

**Anonymous report**:
A report sent without a citizen session. It stays anonymous forever.

**Own report**:
A report the signed-in citizen sent.

**Test account** (UI *Cuenta de prueba*):
A temporary local mode of the MVP app for testers. It sends reports anonymously.

## App

**Inicio**, **Avisos**, **Reportar**, **Mis reportes**, **Perfil**:
The five tabs of the app's bottom bar, always with these names.

**Report flow** (UI *Reportar*):
The step-by-step screens that create one report: **Ubicación → Categoría → Foto → Detalles → Revisar y enviar**, then
the **result**.
_Avoid_: wizard (only in old docs), form

**Result** (UI *Resultado*):
The screen after sending that shows the verifier's verdict and what to do next.

**Draft** (UI *Borrador*):
A report the citizen has not finished. It lives only on the device.
_Avoid_: pending report

**Outbox** (UI *Por enviar*):
Finished reports that wait on the device for network. The app sends them again by itself.
_Avoid_: queue (the portal's triage queue), pending

**Idempotency key**:
The one id a report keeps on the device from draft to sent, so that a retry never makes a second report.

**Follow** (UI *Seguir este reporte*, heart icon):
To watch a report the citizen did not send. Follows live on the device only.
_Avoid_: favorite, like, subscribe

**Notice** (UI *Aviso*):
A message in Avisos that a report the citizen owns or follows changed state. Not a push notification.
_Avoid_: notification, alert

**Explorar** (UI *Explorar mi ciudad*):
The full-screen map and list of public reports, opened from Inicio. Details in the [app glossary](app/GLOSSARY.md).

**Onboarding**:
The three slides on first run.

## Portal

**Portal**:
The web application of the municipality: a public part and a staff part.
_Avoid_: dashboard (that is one page), web app, admin panel

**Mapa**:
The portal's public map and list of reports.

**Report page**:
The public page of one report with photo, state and timeline. Shared links open it.

**Panel** (`stats`):
The portal's statistics page for the municipality.
_Avoid_: dashboard in UI text

**Staff mode** (UI *Modo personal*):
The portal after a staff member signs in: transitions, notes, assignment and the triage queue are available.

**Triage queue** (`queue`, UI *Triaje*, *Bandeja de revisión*):
The staff list of reports that wait for a first decision: new reports with no assignee, and verifier rejections.
_Avoid_: inbox, backlog

**Pin**:
One report on a map, colored by state group.

**Cluster**:
One map mark that stands for several close reports, with their count.

## Integration

**Open311**:
A read-only view of verified reports in the Open311 GeoReport v2 standard, for municipal IT systems. In it, a category
is called a **service** and a report a **service request**; use those words only there.

**CSV export**:
The download of filtered reports as a spreadsheet file, without personal data.

**API contract**:
[`documentation/api-contract.md`](documentation/api-contract.md), the binding description of every endpoint and field.
A term in this glossary that has a contract identifier must match the contract.
