// Case detail: header, key facts, before/after photos, history, and the status form at the bottom.

import { h } from "./dom.js";
import { formatDateTime, formatDays, plural, relativeTime } from "./format.js";
import { categoryLabel } from "../domain/categories.js";
import { allowedTransitions, statusLabel } from "../domain/statuses.js";
import { CREDIBILITY_LABELS } from "../domain/cases.js";
import { SEVERITY_LABELS } from "../domain/schema.js";
import { slaDays } from "../domain/priority.js";
import { priorityLevel } from "./views.js";

const SVG_NS = "http://www.w3.org/2000/svg";
const KIND_TEXT = {
  report: "Reporte de un vecino",
  confirm: "Confirmación de un vecino",
  repair_check: "Foto de después",
};
const VERIFY_TEXT = { passed: "foto verificada", failed: "foto rechazada", pending: "foto en revisión" };

function icon(path) {
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("class", "icon");
  for (const d of path) {
    const p = document.createElementNS(SVG_NS, "path");
    p.setAttribute("d", d);
    svg.append(p);
  }
  return svg;
}
const ICON_BACK = ["M15 18l-6-6 6-6"];
const ICON_CAMERA = ["M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z", "M12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"];
const ICON_ALERT = ["M12 9v4M12 17h.01", "M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"];

function photo(url, label, caption, emptyText) {
  return h(
    "figure",
    { class: "photo" },
    url
      ? h("img", { src: url, alt: `${label}: ${caption}`, loading: "lazy" })
      : h("div", { class: "placeholder" }, icon(ICON_CAMERA), emptyText),
    h("figcaption", {}, h("b", {}, label), ` · ${caption}`),
  );
}

function timeline(c) {
  const items = [
    ...c.reports.map((r) => ({
      at: r.createdAt,
      title: KIND_TEXT[r.kind],
      who: VERIFY_TEXT[r.verification.status],
      text: r.verification.status === "failed" && r.verification.reason ? r.verification.reason : "",
      dot: r.verification.status === "failed" ? "dot tl-failed" : "dot tl-report",
      photoUrl: r.kind === "repair_check" ? r.photoUrl : undefined,
    })),
    ...c.history.map((e) => ({
      at: e.at,
      title: statusLabel(e.status),
      who: e.by === "gobierno" ? "Gobierno" : e.by === "vecino" ? "Vecino" : "Sistema",
      text: e.note ?? "",
      dot: `dot st-${e.status}`,
    })),
  ].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));

  return h(
    "ol",
    { class: "timeline" },
    items.map((it) =>
      h(
        "li",
        {},
        h("span", { class: "tl-rail" }, h("i", { class: it.dot })),
        h(
          "span",
          { class: "tl-body" },
          h("span", {}, h("b", {}, it.title), h("span", { class: "who" }, ` · ${it.who}`)),
          h("small", {}, h("time", { datetime: it.at }, formatDateTime(it.at)), it.text ? ` · ${it.text}` : ""),
          it.photoUrl ? h("img", { src: it.photoUrl, alt: it.title, loading: "lazy", class: "tl-thumb" }) : null,
        ),
      ),
    ),
  );
}

function statusForm(c, { onChangeStatus, onSimulate }) {
  const options = allowedTransitions(c.status);
  const demo =
    onSimulate && c.open
      ? h(
          "div",
          { class: "demo-tools" },
          "Demo:",
          h("button", { type: "button", class: "btn", onClick: () => onSimulate(c.id, true) }, "Foto de después: reparado"),
          h("button", { type: "button", class: "btn", onClick: () => onSimulate(c.id, false) }, "Sigue dañado"),
        )
      : null;

  if (options.length === 0) {
    const text =
      c.status === "fix_claimed"
        ? "Esperando la foto de después de un vecino. El caso se cierra solo cuando el verificador la aprueba."
        : c.status === "fixed"
          ? "Caso cerrado con prueba de reparación."
          : "No hay cambios de estado disponibles.";
    return h("div", { class: "status-form" }, h("p", { class: `hint${c.status === "fixed" ? " done" : ""}` }, text), demo);
  }

  const select = h("select", { id: "status-next" }, options.map((s) => h("option", { value: s }, statusLabel(s))));
  const note = h("textarea", { id: "status-note", rows: "1", maxlength: "500", placeholder: "Nota para el historial (opcional)", "aria-label": "Nota" });
  const error = h("p", { class: "form-error", role: "alert", hidden: true });
  const button = h("button", { type: "submit", class: "btn primary" }, "Guardar");
  const form = h(
    "form",
    { class: "status-form" },
    h("label", { for: "status-next" }, "Cambiar estado"),
    h("div", { class: "form-row" }, select, button),
    note,
    error,
    h("p", { class: "hint" }, "El caso solo se marca como reparado cuando el verificador aprueba la foto de después."),
    demo,
  );
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

export function renderDetail(el, c, { now, onBack, onChangeStatus, onSimulate, onExport }) {
  const level = priorityLevel(c);
  const warn = [];
  if (c.open && c.severity === "dangerous") warn.push("Peligroso");
  if (c.overdue) warn.push("vencido");

  const back = h("button", { type: "button", class: "back", onClick: onBack }, icon(ICON_BACK), "Cola de trabajo");
  const exportBtn = h("button", { type: "button", class: "btn quiet", onClick: () => onExport(c) }, "Descargar (Open311)");

  el.replaceChildren(
    h(
      "div",
      { class: "detail-body" },
      h("div", { class: "detail-top" }, back, h("span", { class: "folio" }, c.id)),
      h(
        "div",
        { class: "detail-head" },
        h("h2", { class: "detail-title" }, categoryLabel(c.category)),
        h("p", { class: "detail-address" }, c.address ?? "Sin dirección", c.zone && !(c.address ?? "").includes(c.zone) ? ` · ${c.zone}` : ""),
        h(
          "div",
          { class: "pills" },
          h("span", { class: `pill${c.status === "fixed" ? " good" : ""}` }, h("i", { class: `dot st-${c.status}` }), statusLabel(c.status)),
          warn.length > 0 ? h("span", { class: "pill bad" }, icon(ICON_ALERT), warn.join(" · ")) : null,
          h("span", { class: "pill" }, CREDIBILITY_LABELS[c.credibility]),
        ),
      ),
      h(
        "dl",
        { class: "facts" },
        h("div", {}, h("dt", {}, "Reportado por"), h("dd", {}, plural(c.reporterCount, "vecino", "vecinos"))),
        h("div", {}, h("dt", {}, "Primer reporte"), h("dd", {}, relativeTime(c.firstReportedAt, now))),
        h(
          "div",
          {},
          h("dt", {}, c.status === "fixed" ? "Reparado en" : "Plazo"),
          h("dd", {}, c.status === "fixed" ? formatDays(c.daysToFix) : `${slaDays(c.severity)} días${c.overdue ? " · vencido" : ""}`),
        ),
        h(
          "div",
          {},
          h("dt", {}, level ? "Prioridad" : "Gravedad"),
          h("dd", {}, level ? `${level.label} · ${c.priority}` : SEVERITY_LABELS[c.severity]),
        ),
      ),
      h(
        "div",
        { class: "photos" },
        photo(c.beforePhotoUrl, "Antes", c.beforePhotoUrl ? "verificada" : "en revisión", "Sin foto verificada todavía"),
        photo(c.afterPhotoUrl, "Después", c.afterPhotoUrl ? "verificada" : "cierra el caso", "Esperando foto de un vecino"),
      ),
      h("h3", { class: "section-title" }, "Historial"),
      timeline(c),
      exportBtn,
    ),
    statusForm(c, { onChangeStatus, onSimulate }),
  );
}
