# Push notifications for citizens (requirements)

Status: draft, 2026-11-20 (Fernando). Nothing is built yet. The app today records state changes in **Avisos** only when it
refreshes reports; `mobile-release.md` configures no push or background capability.

## Goal

Tell a citizen, without opening the app, that the municipality moved a report they created or follow. Avisos stays the
source of truth: every push also appears there, and a citizen who refuses push loses nothing except the interruption.

## Decisions

1. **Events that notify:** municipal progress, resolution or closing, for reports the citizen created **and** reports they
   follow. The photo verification result does **not** notify: the citizen sees it on the result screen seconds after sending.
2. **Who receives push:** any installation, including anonymous ones. Phone verification is not required, which keeps the
   onboarding promise that no account is needed.
3. **When to ask for permission:** after the first report is sent, on the result screen, never at first launch. If the
   citizen says no, the app does not ask again; they can turn it on later in **Perfil**.
4. **Provider:** Firebase Cloud Messaging (FCM) for Android, and for iOS through FCM with an APNs key.

## Events and text

States come from the [contract v0.2 case table](../api-contract.md). The title is the report category; the body is fixed
text (no staff names, no internal notes). Copy follows the app's register (tú) until the copy review decides otherwise.

| Transition (`to_state`) | Push | Body (Spanish) |
|---|---|---|
| `en_revision` | yes | El municipio está revisando tu reporte. |
| `programado` | yes | La atención de tu reporte ya tiene fecha. |
| `en_proceso` | yes | Se está trabajando en tu reporte. |
| `resuelto` | yes | El municipio informa que el problema fue atendido. |
| `no_procede` | yes | El municipio cerró tu reporte. Consulta el motivo en Aldia. |
| `fuera_de_competencia` | yes | Este problema lo atiende otra institución. Consulta el motivo en Aldia. |
| `duplicado` | yes | Tu reporte se unió a otro sobre el mismo problema. |
| `resuelto` → `en_revision` (reopen) | yes | El municipio volvió a abrir tu reporte. |
| `nuevo`, `rechazado_verificador`, `pendiente_verificacion` | no | Shown on the result screen. |
| `oculto` and its restore | no | Moderation is not announced. |
| Backward move between open states | no | Avoids noise from staff corrections. |

For a followed report, "tu reporte" becomes "un reporte que sigues".

## Behavior (proposed)

- Tapping a push opens the report detail; if the report is no longer public, the app shows "No disponible".
- One push per report per state change. Changes made within 10 minutes on the same report collapse into the latest one.
- No push between 21:00 and 07:00 Guatemala time; those are delivered at 07:00 (only the latest per report).
- **Perfil** has one switch, "Avisos en el teléfono". Unfollowing a report stops its push.
- **Borrar mis datos** and turning the switch off delete the device token on the server.

## Privacy

- The payload carries only the report id, the new state and the fixed text. No coordinates, photo, phone number or name.
- Anonymous reports have no owner on the server, so the device must register which report ids it wants to hear about.
  That links one installation to its reports on the server. It must be disclosed in the store privacy forms
  ([mobile-release.md](../mobile-release.md)) and in the app's privacy text.
- The server keeps the token only while it is active; FCM tokens that fail delivery are deleted.

## What each area needs

- **API (Lorenz):** a contract change for device registration (token, platform, subscribed report ids, opt-out) and a sender
  that runs after `POST /api/reports/{id}/transition`. Announce it in the contract first.
- **App (Fernando, Helmut):** Firebase messaging plugin (new dependency, to be approved), permission prompt on the result
  screen, token refresh, tap handling, Perfil switch, Avisos entry for each push.
- **Accounts (Helmut):** Firebase project, Android app registration, APNs key (needs the paid Apple developer account).

## Open questions

- Quiet hours and the 10-minute collapse window: confirm with a municipality.
- Should a `public_note` from staff be included in the push body (it is public already), or only shown in Avisos?
- Report ids per device: is there a limit (for example 200) to bound storage?
