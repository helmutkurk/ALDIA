# Usability test: Phase 2 prototype

Test plan for 3–5 sessions with the low-fi clickable prototype (Figma file "Aldia - prueba MCP", page "Wireframes
low-fi"). Facilitator instructions are in English; everything said to participants is in Spanish (Guatemala).

## 1. Goals

Find out, before writing app code, whether citizens can:

1. understand what Aldia is for after onboarding;
2. find reports near them on the map, read the state colors and open a report;
3. narrow the map with filters and switch to the list;
4. report a problem from start to end, including the conditional "¿Es este tu reporte?" step and the phone
   verification that now appears only when sending;
5. understand a rejected photo and know what to do next;
6. find how their report is going (Avisos or Mis reportes).

We are testing the design, not the person. A task that fails is a finding.

## 2. Participants

- 3–5 adults who live in Guatemala and use a smartphone daily. Mix ages, and include at least one person who rarely
  uses apps beyond messaging. Nobody from the team, and nobody who has seen the prototype.
- **Privacy (public repository):** never write names, phone numbers, faces, addresses or recordings in the repo.
  Use codes **P1–P5**. Keep any recording (only with consent) outside the repo and delete it after the synthesis.
- The prototype contains only synthetic data. Participants never type real phone numbers: the prototype fields are
  not live.

## 3. Setup

- Phone with the Figma app (or a laptop sharing the Figma prototype in Present mode at phone size).
- Start each task from the flow named in the task table (Present → flow list).
- Facilitator + one note-taker if possible. Session length: 30–40 minutes.
- Prototype limits to keep in mind: text fields do not accept input, chips do not toggle, only the main path is linked.
  When a participant hits a limit, say "En el prototipo eso no funciona todavía; ¿qué esperarías que pase?" and note
  the answer.

## 4. Script (read aloud)

**Introducción**
> Gracias por ayudarnos. Estamos diseñando una aplicación para reportar problemas de la calle, como baches o
> luminarias dañadas. Vamos a probar un borrador: no es la versión final y muchas partes son grises a propósito.
> No te estamos evaluando a ti; si algo es difícil, es culpa del diseño y eso es justo lo que queremos encontrar.
> Por favor, piensa en voz alta: dinos qué ves, qué buscas y qué esperas que pase.

**Consentimiento**
> Vamos a tomar notas sin tu nombre. ¿Está bien? ¿Podemos grabar la pantalla (no tu cara) solo para revisar
> nuestras notas? La grabación se borra después. Puedes parar cuando quieras.

Record only a yes/no for each question in the session sheet.

**Preguntas iniciales (2 min)**
1. ¿Alguna vez has reportado un problema de la calle a la municipalidad? ¿Cómo lo hiciste?
2. ¿Qué apps usas más en tu teléfono?

## 5. Tasks

Read each task card aloud and hand over the phone. Do not help unless the participant is stuck for about a minute;
then give the smallest hint and mark "con ayuda".

| # | Flow / start frame | Task card (Spanish) | Success when | Watch for |
|---|---|---|---|---|
| T1 | 1 · Primer uso (A1) | "Acabas de instalar Aldia. Empieza a usarla y cuéntanos para qué crees que sirve." | Reaches Inicio and explains the purpose in their words | Skips onboarding? Understands that photos are public? |
| T2 | 2 · Explorar (A2) | "Quieres saber si alguien ya reportó problemas cerca de ti. Búscalos en el mapa y abre uno." | Opens Explorar, taps a pin, reaches the detail | Finds "Explorar mi ciudad"; reads the legend; understands clusters with numbers |
| T3 | from A3 | "Ahora quieres ver solo los baches que ya están resueltos." | Opens the filter sheet and taps "Aplicar filtros" (chips do not toggle) | Finds the filter button; understands categoría vs. estado; expects search here? |
| T4 | from A3 | "Mira los mismos reportes como lista." | Uses the Mapa / Lista switch | Notices the switch; expects the filters to stay |
| T5 | 1 · Primer uso, from A2 | "Frente a tu casa hay un bache grande. Repórtalo." | Reaches "Reporte enviado" (B9) | Location step understood; reaction to "¿Es este tu reporte?" (follow vs. continue); live-photo rule; reaction to the phone request at the end; public-photo notice |
| T6 | show B10 | "Imagina que después de enviar ves esta pantalla. ¿Qué pasó y qué harías?" | Explains that the photo must be retaken and why | Reads the reasons; trusts the result; "Falta ajustar la foto" wording |
| T7 | 3 · Seguimiento (C1) | "Ayer enviaste un reporte. Quieres saber cómo va." | Finds it in Mis reportes or Avisos and opens the detail | Which tab they choose; understands "Por enviar" and "Borradores"; unread dot |
| T8 | show B11 | "Enviaste un reporte sin señal y ves esto. ¿Qué crees que pasó con tu reporte?" | Says it will be sent later without doing anything | Worry about losing the report; looks for it in Mis reportes |

After each task, ask: **"Del 1 al 7, ¿qué tan fácil fue? (1 = muy difícil, 7 = muy fácil)"**

**State words check (after T7, 2 min):** point at "Recibido", "En revisión", "En proceso", "Resuelto", "Cerrado" and ask
"¿Qué significa esto para ti?". Note any word that is misread.

**Cierre**
1. ¿Qué fue lo más confuso?
2. ¿Qué te gustó?
3. ¿Usarías algo así? ¿Qué te haría dejar de usarlo?
4. ¿Te molestó que te pidiéramos el teléfono al enviar? ¿Preferirías otra forma (por ejemplo, el DPI)?

## 6. Session sheet (copy one per participant)

```
Participant: P_   Date: ____   Device: ________   Consent notes: yes/no   Recording: yes/no

| Task | Result (sí / con ayuda / no) | Ease 1–7 | Time (opt.) | Observations | Quotes (no names) |
|------|------------------------------|----------|-------------|--------------|-------------------|
| T1   |                              |          |             |              |                   |
| T2   |                              |          |             |              |                   |
| T3   |                              |          |             |              |                   |
| T4   |                              |          |             |              |                   |
| T5   |                              |          |             |              |                   |
| T6   |                              |          |             |              |                   |
| T7   |                              |          |             |              |                   |
| T8   |                              |          |             |              |                   |

Misread state words:
Closing answers:
```

## 7. Synthesis (after the last session)

1. Put every observation on one list; merge duplicates; count how many participants hit each one.
2. Rate each issue: **3 = blocks the task**, **2 = slows or confuses**, **1 = cosmetic**.
3. Fill the table below and decide a change for every issue rated 3, and for issues rated 2 that affect two or more people.

| Issue | Screens (frames) | Participants (n/N) | Severity | Proposed change | Owner |
|---|---|---|---|---|---|
| | | | | | |

Store the synthesis as `app/docs/ux/usability-results.md` (codes only, no personal data), update the wireframes, then
start Phase 3.
