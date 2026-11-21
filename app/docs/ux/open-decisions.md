# Open decisions (questions for the team)

Phase 1 UX spec, 2026-11-21. Each item is something undefined, inconsistent or contradictory between the code and the docs.
"Proposed owner" is a suggestion from the roles in `AGENTS.md`, not an assignment. ★ = blocks the Phase 2 wireframes.

**Update 2026-11-21:** the ★ items 1, 2, 7, 13, 20, 21, 22 and 23 are decided in
[`documentation/decisions/ux-2026-11-21.md`](../../../documentation/decisions/ux-2026-11-21.md) (marked ✅ below).
Item 26: the app stays Flutter. Item 27: specs stay in `app/docs/ux/` for now. All other items remain open.

## Account and login

1. ✅ *Decided: phone code; citizen ID (DPI) possible later.* ★ **Which login method is final?** `documentation/decisions/citizen-login.md` chose a six-digit phone code and it is
   built. `app/README.md` says "the login method (citizen ID or email) is undecided" and adds the MVP test account.
   Is it phone code, citizen ID (DPI), email, or more than one? *(Fernando, Helmut, Lorenz)*
2. ✅ *Decided: at send (option b).* ★ **When must the citizen sign in?** The decision says "at the final report step". The reference (SeeClickFix) asks at
   submit, as an optional "register to receive updates". The code asks at app start and blocks everything
   (`REQUIRE_CITIZEN_LOGIN` app default `true`), while the API default is `false`. Options: (a) login first,
   (b) browse freely, login at submit, (c) anonymous reports allowed, login only for notices. *(app + backend)*
3. **When is the test account removed?** It sends reports without credentials, so it forces the API to stay in optional
   login mode. Is it only for the government demo?
4. **Display name:** it can only be set during verification and never changed. Do we need an edit screen in Perfil, and
   must alias removal also remove it from old reports? (Not implemented, per the decision.)
5. **Account deletion:** **Borrar mis datos** deletes local data only. Do we need "delete my account" before a pilot?
6. **Phone numbers outside Guatemala:** the UI fixes `+502`, but the geocoder and the verifier accept Guatemala, Colombia
   and Mexico. Is the pilot Guatemala-only?

## Report flow

7. ✅ *Decided: only when the API finds matches.* ★ **Do we show nearby reports before the photo?** The reference and `documentation/ui/app-ui-notes.md` include an
   "Is this your request?" step; the code removed it (README) and only shows duplicates **after** sending. A pre-check
   avoids uploads and duplicates but adds a step. Keep removed, restore, or show it only when matches exist?
8. **Manual review:** after three rejections, **Enviar para revisión manual** only saves locally and says it is not
   available. Build the server/portal side, or hide the button until it exists?
9. **"Other" category:** there are six fixed categories and no "Otro". What does a citizen do with a problem that fits
   none? The final list depends on what the verifier can recognize (Lorenz).
10. **Address on reports:** the API has no address field, so cards show coordinates. Do we add a street/zone field
    (reverse geocoding on the server) so that cards and the Dashboard can show places people understand?
11. **Consent screen:** the MVP plan asks for privacy text and consent before the first report. What must the text say,
    and who approves it (legal review with the partner municipality)?
12. **Queued reports and account switching:** an unsent outbox item uses the account active when it is finally sent.
    Bind items to the account at creation, or block sign-out while items are queued?

## States and wording

13. ✅ *Decided: citizen words in the app and public portal; official words in staff screens.* ★ **Citizen and staff state names differ.** Same contract state, different words:

    | state | App (citizen) | Portal (staff/public) |
    |---|---|---|
    | `pendiente_verificacion` | En verificación | Pendiente de verificación |
    | `rechazado_verificador` | Falta ajustar la foto | Rechazado por verificador |
    | `nuevo` | Recibido | Nuevo |
    | `no_procede` | Cerrado | No procede |
    | `fuera_de_competencia` | Corresponde a otra entidad | Fuera de competencia |
    | `duplicado` | Ya estaba reportado | Duplicado |
    | `oculto` | No disponible | Oculto |

    Is this intentional (friendly citizen words vs. official staff words)? The public portal map is also seen by
    citizens; which wording does it use? A shared link opens the portal, so the same report shows two names.
14. **Legacy fallback differs.** For a report without `state` and `resolution: "closed"`, the app shows `no_procede`
    and the portal shows `nuevo` (`app/lib/data/report.dart` vs `portal/src/states.js`). Which is right? (Only affects
    v0.1-shaped data, but it is a real inconsistency.)
15. **Verifier test label.** The README says "a stub verifier is always labeled as a test", but the verifier now
    answers `mode: "heuristic"` and never `stub`. The app only labels `stub`, so citizens see "Reporte verificado"
    without any caveat. The portal has a heuristic note. Should the app say that checks are technical, not proof?

## Notices and engagement

16. **Avisos without push:** is a tab with a manual refresh worth its place in the bottom bar before push exists? If yes,
    do we need unread markers and a badge? Which push provider (FCM/APNs) and when?
17. **Follows are device-local.** Should follows sync to the account (needs an API) so they survive a new phone?
18. **Inicio counter period:** the counter uses the API's default window (last 90 days); the reference shows "fixed all
    time". Which number do we promise, and what label explains it?
19. **Rewards** are "to be defined" (decision 2026-11-19). Confirm that no reward UI is designed in Phase 2.

## Visual design (see design-direction.md)

20. ✅ *Decided: app and portal change together.* ★ **New palette vs. binding shared tokens.** `documentation/design-tokens.md` (Helmut, 2026-11-20) binds the app *and*
    the portal to the calm teal/graphite palette. The new direction (Guatemala sky blue + coral) changes both. Do Isa
    and Helmut agree to change the shared tokens, or does only the app change? (Changing only the app breaks
    "app and portal share these values".)
21. ✅ *Decided: fixes accepted.* ★ **Contrast of the given colors.** White on `#2F7FBF` is 4.28:1 and white on `#FF7A59` is 2.57:1; both fail the
    4.5:1 rule that `test/core/theme_test.dart` enforces. Accept the proposed darker values in design-direction.md?
22. ✅ *Decided: new status set.* **Status colors collide with the new brand.** Open = orange `#E8731A` is close to the coral accent; resolved = blue
    `#2D8CD0` is close to the sky-blue primary. Re-map status colors, or keep them and pick quetzal green as the accent?
23. ✅ *Decided: coral.* **Coral or quetzal green** as the accent?
24. **Dark top bar:** the current Inicio and Explorar use a dark graphite `bar`. The new direction asks for white
    backgrounds and light cards. Do we drop the dark bar?
25. **Inicio content:** the new references (category grid, metric cards with a chart) suggest a richer home than today's
    counter + two buttons. Which of these does the citizen home get? **Assumption:** metric cards with charts belong
    mainly to the Dashboard.

## Platform and process

26. ★ **Platform reality.** The Phase 1 brief speaks of an Android app with Jetpack Compose. The app is Flutter for
    Android, iOS and a Linux demo. Confirm Flutter stays, and that "@Preview" in Phase 3 means Flutter widget previews
    (or golden/widget tests), not Compose.
27. **Where do UX specs live?** These files are in `app/docs/ux/` (the app's folder, per the role rule). Shared items
    (dashboard-shared.md) may belong in `documentation/` once Isa reviews them.
28. **Language:** Perfil shows "Idioma: Español (Guatemala)" with no choice. Are other languages (K'iche', English) in
    scope for the pilot?
29. **White-label city name:** the reference home shows the city's name. Is Aldia one app per municipality, or one app
    for all with a city picker?
