# Five-minute municipal demo

All cases, crews, notes and images are synthetic. Locations illustrate a compact
neighborhood around Zona 4, Guatemala City; they do not allege defects at real
addresses. Never present seeded verification results as measurements of real
photos or the trend as evidence of municipal performance.

## Prepare before the meeting

1. Start the local stack and migrate the database following the API README.
   Use an isolated demo database and private photo directory. Set `ENV=dev`.
   Run `make seed` in the presenter's private terminal. The seed is idempotent;
   if this database already contains an older storyline, run
   `uv run python scripts/seed_demo.py --reset` from `backend/api` to replace
   **only `[demo]` reports**. Never reset a deployment containing real cases.
   Demo account creation can display initial credentials; keep that terminal off
   the projector. Have the operator account ready through the normal login UI.
2. Open the app and portal at `http://localhost:5173`. Confirm camera permission,
   API connectivity and verifier health. Rehearse a fresh camera capture of a
   **printed synthetic street illustration**, with no people or personal data.
   A heuristic rejection is a valid outcome; do not promise classification or
   bypass the verifier to force a pass. The live category check has no trained
   model. Seeded verdicts use `mode: stub` and are explicitly illustrative.
3. Bookmark the three comparison cases below and open the panel using
   `http://localhost:5173/#/panel?include_old=true`. Keep category, state and date
   filters clear and the map broad enough to include Zona 4. The normal list
   defaults to 30 days; **Más filtros → Incluir reportes antiguos** enables the
   complete story. The seed has 62 reports, 60 publicly visible, all six
   categories, 26 resolved, three staff duplicates and three verifier rejections.
   Two hidden reports are available only to authorized staff.
4. Record the baseline Panel totals before creating the live case. Prepare the
   seeded comparison and rejection tabs so the five-minute story remains usable
   if a camera, map tile provider or network connection fails. The click labels
   below are taken from the current source; rehearse on the actual device and
   browser before presenting.

## Walkthrough and spoken copy

| Time | Exact action | Say in Spanish |
| --- | --- | --- |
| 0:00–1:10 | In the app, tap **Reportar**. In **Ubicación**, set **Latitud** `14.6260`, **Longitud** `-90.5160`, tap **Usar estas coordenadas**, then **CONFIRMAR UBICACIÓN**. This demo point is outside the seeded duplicate radius. Select **Bache**, tap **Siguiente**, inspect **¿Ya está reportado?**, then **Es un problema distinto**. In **Foto**, tap **Tomar foto** (or the camera icon), photograph the printed synthetic illustration, confirm the camera capture and tap **Usar esta foto**. In **Detalles**, enter `[demo] Bache de ensayo en el cruce D.`; tap **Siguiente**, review and tap **Enviar reporte**. | “Una vecina indica dónde está el problema, revisa si alguien ya lo reportó y toma una foto en el momento. Esta captura y este lugar son una simulación, sin datos de ciudadanos.” |
| 1:10–1:50 | On the result screen, read **Verificación** and its individual checks. A pass shows **Reporte verificado**; a rejection shows **La foto no pasó la verificación**, with **Tomar otra foto** available. A verifier outage shows **Reporte recibido, verificación pendiente**. Tap **Cerrar**, then **Mis reportes**, and open the new report. In the portal, click **Modo personal**, enter the prepared operator account and click **Iniciar sesión**; click **Triaje → Rechazadas por verificador** and open one seeded rejected case to show its reason. | “El sistema explica cada comprobación: legibilidad, antigüedad y posibles duplicados. Estas comprobaciones no prueban autenticidad ni reconocen todavía el tipo de daño. Un rechazo explica qué corregir; una caída del verificador conserva el reporte como pendiente.” |
| 1:50–2:45 | Click **Triaje → Por revisar**. Open a case by its category link, preferably the new live case if verified. The queue is oldest first: use **Siguiente** if necessary, or open the report using the app reference at `/#/reports/<id>`. For a seeded fallback, open a **Nuevo** case. Under **Cambiar estado**, choose **Nuevo estado → En revisión**, enter **Nota pública** `[demo] Recibimos su reporte y lo estamos revisando.`, and click **Guardar**. Set **Cuadrilla o responsable** to `Cuadrilla de movilidad Zona 4` and click **Asignar**. | “El personal trabaja con una bandeja, asigna una cuadrilla y deja un mensaje que también puede leer la ciudadanía. Los cambios conservan fecha, usuario y estado anterior.” |
| 2:45–3:45 | In the same case, choose **Programado**, enter `[demo] Cuadrilla programada para el jueves.` in **Nota pública**, and **Guardar**. Then choose **En proceso**, enter `[demo] La cuadrilla inicia la reparación de ensayo.`, **Guardar**; choose **Resuelto**, enter `[demo] Reparación de ensayo terminada; se comprobó el paso peatonal.`, **Guardar**. Scroll to **Historial de estados**. Open a comparison bookmark and click **Ampliar foto** to show **ANTES / DESPUES**. | “Aquí avanzamos varios días en segundos para explicar el proceso. En una operación real solo se marca resuelto después de comprobar la reparación. Este otro caso contiene ilustraciones del antes y después, claramente identificadas como sintéticas.” |
| 3:45–5:00 | Click **Panel**, enable **Incluir reportes antiguos** under **Más filtros** if necessary, and clear other filters. Compare the resolved count to the baseline: exactly one more when one previously open case was closed. Show **Recibidos y resueltos por semana**, **Acumulado en el periodo consultado**, **Tiempo de reparación por categoría**, and expand **Ver tabla** for the category chart. Show the CSV export control and the integration document for IT. | “Pasamos del caso individual al seguimiento del servicio. La historia de demostración muestra una proporción acumulada de resueltos que aumenta cada semana. La tabla permite revisar los números, incluidos los tamaños de muestra. Los datos se pueden exportar y consultar por API y Open311; este ejemplo no acredita resultados reales.” |

If the live capture is rejected, continue with the seeded **Nuevo** fallback;
leave the rejection visible and explain its actual reason. If the verifier is
unreachable, do not call the pending report verified. One report closure is the
only expected live dashboard change; reload the panel if it was already open.
A real app report and its note must retain the `[demo]` prefix for later cleanup.

## Stable before-and-after cases

The current report contract has **one photo per report**. Each case therefore
uses a single 800 × 600 JPEG containing two distinct Pillow-generated scenes,
marked **ANTES** and **DESPUES**, rather than separate uploads or proof-of-work
attachments. The existing `photo_url` and **Ampliar foto** display the composite;
there is no after-photo upload feature in this version.

| Case | Portal link |
| --- | --- |
| Cruce A: accessibility ramp | [Open case](http://localhost:5173/#/reports/9676ef9c-9a6d-5340-ab7c-e8c3aeaf40a1) |
| Pasaje B: repaired sidewalk | [Open case](http://localhost:5173/#/reports/5563a60a-3443-5b64-8791-7378175de63f) |
| Calle C: repaired pothole | [Open case](http://localhost:5173/#/reports/c75c1091-f6ef-5d35-8edf-62df5e1d1bae) |

These links remain stable after reseeding. Idempotence preserves existing rows;
use the isolated-demo `--reset` step to replace an older seed with this story.
`--purge` removes `[demo]` report rows, events, idempotency records and photos;
it does not remove staff accounts.

## Evidence behind the trend

The seed places an initial backlog 60 days ago, a neighborhood inspection
29 days ago and repairs across the following weeks. Notes and events are in
Spanish. Every resolved case has a full review → scheduling → work → resolution
chain, with ordered dates before the seed time. Each category retains three
explicit repair-duration samples within the default 30-day dashboard window.

For a fresh seed anchored at `2026-11-20T18:00:00Z`, the portal's weekly series
has the following cumulative values (weeks use `America/Guatemala`). Counts
exclude hidden reports and the two still awaiting verification, matching
`weekly[].recibidos`; the seed summary prints the same calculation.

| Week | Cumulative received | Cumulative resolved | Resolved / received |
| --- | ---: | ---: | ---: |
| 2026-W39 | 13 | 0 | 0.0% |
| 2026-W40 | 19 | 1 | 5.3% |
| 2026-W41 | 24 | 2 | 8.3% |
| 2026-W42 | 28 | 3 | 10.7% |
| 2026-W43 | 50 | 13 | 26.0% |
| 2026-W44 | 55 | 19 | 34.5% |
| 2026-W45 | 56 | 21 | 37.5% |
| 2026-W46 | 58 | 24 | 41.4% |
| 2026-W47 | 58 | 26 | 44.8% |

The displayed **Tasa de resolución** has a different, documented denominator:
it also excludes three staff duplicates and two cases outside municipal
competence, so the all-history baseline is `26 / 53 = 49.1%`. Do not label the
44.8% cumulative series ratio as that KPI. With an otherwise empty demo database,
closing one seeded open case changes the resolved count from 26 to 27. Creating
and resolving a new verified live case changes both received and resolved by one.
Calendar week labels and partial-week counts depend on the actual seed date.
