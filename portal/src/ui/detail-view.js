// Case detail: photos before and after, credibility, the status workflow and the full timeline.

import { h } from "./dom.js";
import { formatDateTime, formatDays, plural, relativeTime } from "./format.js";
import { categoryLabel } from "../domain/categories.js";
import { allowedTransitions, statusLabel } from "../domain/statuses.js";
import { CREDIBILITY_LABELS } from "../domain/cases.js";
import { SEVERITY_LABELS } from "../domain/schema.js";
import { slaDays } from "../domain/priority.js";

const KIND_TEXT = {
  report: "Reporte de un vecino",
  confirm: "Confirmación de un vecino",
  repair_check: "Foto de después",
};
const VERIFY_TEXT = { passed: "Foto verificada", failed: "Foto rechazada", pending: "Foto en revisión" };

function photo(url, caption, emptyText) {
  return h(
    "figure",
    { class: `photo${url ? "" : " is-empty"}` },
    url ? h("img", { src: url, alt: caption, loading: "lazy" }) : h("span", {}, emptyText),
    h("figcaption", {}, caption),
  );
}

function timeline(c) {
  const items = [
    ...c.reports.map((r) => ({
      at: r.createdAt,
      title: KIND_TEXT[r.kind],
      text: r.verification.status === "failed" && r.verification.reason ? `${VERIFY_TEXT.failed}: ${r.verification.reason}` : VERIFY_TEXT[r.verification.status],
      tone: r.verification.status,
      photoUrl: r.photoUrl,
    })),
    ...c.history.map((e) => ({
      at: e.at,
      title: `${statusLabel(e.status)} · ${e.by === "gobierno" ? "Gobierno" : e.by === "vecino" ? "Vecino" : "Sistema"}`,
      text: e.note ?? "",
      tone: "status",
    })),
  ].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));

  return h(
    "ol",
    { class: "timeline" },
    items.map((it) =>
      h(
        "li",
        { class: `tl-${it.tone}` },
        h("time", { datetime: it.at }, formatDateTime(it.at)),
        h("b", {}, it.title),
        it.text ? h("span", {}, it.text) : null,
        it.photoUrl ? h("img", { src: it.photoUrl, alt: it.title, loading: "lazy", class: "tl-thumb" }) : null,
      ),
    ),
  );
}

function statusForm(c, { onChangeStatus }) {
  const options = allowedTransitions(c.status);
  if (options.length === 0) {
    const text =
      c.status === "fix_claimed"
        ? "Esperando la foto de después de un vecino. El caso se cierra solo cuando el verificador la aprueba."
        : c.status === "fixed"
          ? "Caso cerrado con prueba de reparación."
          : "No hay cambios de estado disponibles.";
    return h("p", { class: "hint" }, text);
  }
  const select = h(
    "select",
    { id: "status-next", "aria-label": "Nuevo estado" },
    options.map((s) => h("option", { value: s }, statusLabel(s))),
  );
  const note = h("textarea", { id: "status-note", rows: "2", maxlength: "500", placeholder: "Nota para el historial (opcional)" });
  const error = h("p", { class: "form-error", role: "alert", hidden: true });
  const button = h("button", { type: "submit", class: "btn primary" }, "Guardar cambio");
  const form = h("form", { class: "status-form" }, h("label", { for: "status-next" }, "Cambiar estado"), select, note, error, button);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    button.disabled = true;
    error.hidden = true;
    try {
      await onChangeStatus(c.id, select.value, note.value.trim().slice(0, 500));
    } catch (e) {
      error.textContent = e instanceof Error ? e.message : "No se pudo guardar el cambio.";
      error.hidden = false;
      button.disabled = false;
    }
  });
  return form;
}

function demoTools(c, { onSimulate }) {
  if (!onSimulate || !c.open) return null;
  return h(
    "div",
    { class: "demo-tools" },
    h("p", {}, "Solo demo: simula la foto de después que envía un vecino."),
    h("button", { type: "button", class: "btn", onClick: () => onSimulate(c.id, true) }, "Foto de después: reparado"),
    h("button", { type: "button", class: "btn", onClick: () => onSimulate(c.id, false) }, "Foto de después: sigue dañado"),
  );
}

export function renderDetail(el, c, { now, onBack, onChangeStatus, onSimulate, onExport }) {
  const badges = [
    h("span", { class: `chip st-${c.status}` }, statusLabel(c.status)),
    h("span", { class: `badge cred-${c.credibility}` }, CREDIBILITY_LABELS[c.credibility]),
    h("span", { class: `badge sev-${c.severity}` }, SEVERITY_LABELS[c.severity]),
    c.overdue ? h("span", { class: "badge late" }, `Fuera de plazo (${slaDays(c.severity)} días)`) : null,
    c.nearSensitive ? h("span", { class: "badge" }, "Cerca de escuela u hospital") : null,
  ];

  el.replaceChildren(
    h("button", { type: "button", class: "back", onClick: onBack }, "← Volver a la lista"),
    h("p", { class: "folio" }, c.id),
    h("h2", { class: "detail-title" }, categoryLabel(c.category)),
    h(
      "p",
      { class: "detail-address" },
      c.address ?? "Sin dirección",
      c.zone && !(c.address ?? "").includes(c.zone) ? ` · ${c.zone}` : "",
    ),
    h("div", { class: "badges" }, badges),
    h(
      "dl",
      { class: "facts" },
      h("dt", {}, "Reportado por"),
      h("dd", {}, plural(c.reporterCount, "vecino independiente", "vecinos independientes")),
      h("dt", {}, "Primer reporte"),
      h("dd", {}, `${formatDateTime(c.firstReportedAt)} (${relativeTime(c.firstReportedAt, now)})`),
      h("dt", {}, c.status === "fixed" ? "Tiempo de reparación" : "Abierto desde hace"),
      h("dd", {}, formatDays(c.status === "fixed" ? c.daysToFix : c.ageDays)),
      h("dt", {}, "Prioridad"),
      h("dd", {}, c.open ? `${c.priority} de 100` : "—"),
    ),
    h(
      "div",
      { class: "photos" },
      photo(c.beforePhotoUrl, "Antes", "Sin foto verificada todavía"),
      photo(c.afterPhotoUrl, "Después", c.status === "fixed" ? "Sin foto" : "Falta la foto de después"),
    ),
    statusForm(c, { onChangeStatus }),
    demoTools(c, { onSimulate }),
    h("h3", {}, "Historial"),
    timeline(c),
    h("button", { type: "button", class: "btn subtle", onClick: () => onExport(c) }, "Descargar este caso (Open311)"),
  );
}
