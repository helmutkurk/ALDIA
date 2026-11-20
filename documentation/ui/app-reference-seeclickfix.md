# App UI reference: SeeClickFix city apps (screenshots from Helmut, 2026-11-19)

Principles only, in our own words. Do not copy their logo, icons, copy, colors or assets. Aldia keeps its name, Spanish copy and
teal tokens (`documentation/design-tokens.md`). The reference shows white-label city apps (Hilliard OH, Moses Lake WA, Dublin OH).

## Screen by screen (what to reproduce structurally)

1. **Home.** Full-bleed branded header with search icon, city name, locate button and overflow menu. Centered brand mark, one big
   counter ("issues fixed all time"), a thin divider, then two large actions: "Explore your city" and "Report". Bottom navigation with
   five tabs: Home, Notices, New request, Requests, Profile (icon + label; selected tab emphasized; the New request tab is a
   circled plus).
2. **New request, step 1: location.** Full-screen sheet with title, help icon and close button. A summary row (camera avatar + question
   "Is this the correct address?" + place name). Address search field on top of the map; orange pin; layers button; zoom and locate
   controls; a full-width primary button at the bottom: **CONFIRM LOCATION**.
3. **Step 2: category.** Same sheet header ("What is your request?"), a search field "Search for category", then a grouped list:
   group header row, categories below it.
4. **Step 3: nearby requests ("Is this your request?").** Explains that location and category match existing requests; cards with
   category, a heart to follow, address, status (colored dot + word), short description and created date; primary button **NEXT**.
5. **Step 4: photos.** Large circular camera target with "Tap camera to add a photo"; a text link "No photo" (Aldia: NOT allowed; live
   photo is mandatory).
6. **Step 5: submit.** "Register or sign in to receive updates" with two stacked buttons: primary REGISTER, secondary SIGN IN
   (Aldia: phone code instead of email).
7. **Explore: map and list.** Dark top bar (search, place, locate, filter, menu); two tabs MAP and LIST with an accent underline.
   Map: colored status dots, layers button, zoom +/-. List: large photo on top of each card, status word with colored dot aligned
   right, title, address, description, date, request id, heart and share icons.
8. **Status colors:** acknowledged green, open orange, closed blue (always with the word next to the dot).

## Gaps between the current Aldia app and this reference

| Reference | Aldia today | Do |
|---|---|---|
| Home with big "issues fixed" counter and two big actions | Home is the map | Add a landing tab: counter (`resueltos` from `/api/stats`), "Explorar mi ciudad", "Reportar" |
| Bottom nav: Home, Notices, New request, Requests, Profile | Mapa, Lista, Mis reportes + central Reportar | Use: Inicio, Avisos, (Reportar), Mis reportes, Perfil; Mapa/Lista become the two tabs inside "Explorar" |
| Wizard order: location, category, nearby, photo, submit | photo, place, category, nearby, details, review | Reorder to: lugar, categoría, duplicados, foto (live), detalles + revisar/enviar. Category known before the photo also helps the verifier |
| Summary row at the top of every step | none | Add the row (icon + question + place/category chosen so far) |
| Address search + layers + locate on the map step | pin only | Add address search (geocoder interface, Nominatim for the demo, rate-limited), locate button, "CONFIRMAR UBICACIÓN" bottom button |
| Category search + grouped list | chips/rows | Search field + groups from `GET /api/categories` (`group`) |
| Cards with heart (follow) and share | list rows | Cards with large photo, status dot + word, follow (stored locally) and share (WhatsApp share sheet with the public link) |
| Notices tab | none | Inbox fed by state changes of the user's reports (local for now; push later) |
| Profile tab | none | Phone number, name visibility, language note, app version, "borrar mis datos" |
| Dark top bar with MAP / LIST tabs | segmented control | Top app bar + tab bar with accent underline |

## Task list for the app (in this order)

1. Wizard order and summary row.
2. Location step with address search, locate, confirm button.
3. Category step with search and groups.
4. Nearby step as cards with follow (heart), reusing the existing duplicates endpoint.
5. Live photo step (no "no photo" link; keep retake) and review/send.
6. Home landing, new bottom navigation (Inicio, Avisos, Reportar, Mis reportes, Perfil) and Explorar with Mapa/Lista tabs.
7. Cards with large photo, share and follow; Avisos inbox (local); Perfil screen.
Keep all behavior of drafts, outbox and idempotency; keep the Semantics, 48 dp targets and text-scale rules.
