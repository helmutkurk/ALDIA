// KPI tiles, filters, the priority queue and the legend.

import { h } from "./dom.js";
import { formatDays, plural, relativeTime } from "./format.js";
import { CATEGORIES, categoryLabel } from "../domain/categories.js";
import { STATUSES, statusLabel } from "../domain/statuses.js";

export function renderKpis(el, m) {
  const tile = (value, label, tone = "") => h("div", { class: `kpi ${tone}` }, h("b", {}, value), h("span", {}, label));
  el.replaceChildren(
    tile(String(m.openCases), "Casos abiertos"),
    tile(String(m.newReports24h), "Reportes nuevos (24 h)"),
    tile(String(m.urgentUnattended), "Peligrosos sin atender", m.urgentUnattended > 0 ? "alert" : ""),
    tile(String(m.overdue), "Fuera de plazo", m.overdue > 0 ? "warn" : ""),
    tile(String(m.fixedLast30), "Reparados y verificados (30 días)", "good"),
    tile(formatDays(m.avgDaysToFix), "Tiempo promedio de reparación"),
  );
}

export function createFilters(el, initial, onChange) {
  let f = { ...initial, categories: [...initial.categories] };
  const emit = () => onChange({ ...f, categories: [...f.categories] });

  const chips = CATEGORIES.map((c) => {
    const btn = h("button", { type: "button", class: "chip-toggle", "aria-pressed": "false" }, c.label);
    btn.addEventListener("click", () => {
      const on = !f.categories.includes(c.id);
      f.categories = on ? [...f.categories, c.id] : f.categories.filter((x) => x !== c.id);
      btn.setAttribute("aria-pressed", String(on));
      emit();
    });
    return btn;
  });

  const views = [
    ["open", "Abiertos"],
    ["fixed", "Reparados"],
    ["closed", "Cerrados"],
    ["all", "Todos"],
  ];
  const viewButtons = views.map(([id, label]) => {
    const btn = h("button", { type: "button", "aria-pressed": String(f.view === id) }, label);
    btn.addEventListener("click", () => {
      f.view = id;
      viewButtons.forEach((b, i) => b.setAttribute("aria-pressed", String(views[i][0] === id)));
      emit();
    });
    return btn;
  });

  const period = h(
    "select",
    { id: "filter-period", "aria-label": "Periodo" },
    h("option", { value: "0" }, "Todo el tiempo"),
    h("option", { value: "7" }, "Últimos 7 días"),
    h("option", { value: "30" }, "Últimos 30 días"),
  );
  period.addEventListener("change", () => {
    f.periodDays = Number(period.value);
    emit();
  });

  const urgent = h("input", { type: "checkbox", id: "filter-urgent" });
  urgent.addEventListener("change", () => {
    f.urgentOnly = urgent.checked;
    emit();
  });

  const search = h("input", { type: "search", id: "filter-search", placeholder: "Buscar folio, dirección o zona", "aria-label": "Buscar" });
  search.addEventListener("input", () => {
    f.text = search.value.slice(0, 80);
    emit();
  });

  el.replaceChildren(
    h("div", { class: "filter-row" }, h("div", { class: "segmented", role: "group", "aria-label": "Estado" }, viewButtons), period, h("label", { class: "check" }, urgent, "Solo urgentes o vencidos"), search),
    h("div", { class: "filter-row chips", role: "group", "aria-label": "Categorías" }, chips),
  );
}

export function renderLegend(el) {
  const shown = ["new", "in_review", "scheduled", "in_progress", "fix_claimed", "reopened", "fixed"];
  el.replaceChildren(
    ...shown.map((s) => h("span", { class: "legend-item" }, h("i", { class: `dot st-${s}` }), STATUSES[s].label)),
    h("span", { class: "legend-item muted" }, "Número en el punto = vecinos que lo reportaron"),
  );
}

export function renderQueue(listEl, countEl, cases, { selectedId, now, onSelect }) {
  countEl.textContent = `(${cases.length})`;
  if (cases.length === 0) {
    listEl.replaceChildren(h("li", { class: "empty" }, "No hay casos con estos filtros."));
    return;
  }
  listEl.replaceChildren(
    ...cases.slice(0, 300).map((c) =>
      h(
        "li",
        {},
        h(
          "button",
          { type: "button", class: `case-row${c.id === selectedId ? " is-selected" : ""}`, onClick: () => onSelect(c.id) },
          h("span", { class: `prio${c.priority >= 70 ? " hi" : c.priority >= 45 ? " mid" : ""}`, title: "Prioridad (0 a 100)" }, c.open ? String(c.priority) : "—"),
          h(
            "span",
            { class: "row-main" },
            h("span", { class: "row-title" }, categoryLabel(c.category), c.severity === "dangerous" && c.open ? h("em", { class: "flag" }, "Peligroso") : null),
            h("span", { class: "row-sub" }, c.address ?? c.id),
            h("span", { class: "row-sub" }, `${c.id} · ${plural(c.reporterCount, "vecino", "vecinos")}`),
          ),
          h(
            "span",
            { class: "row-meta" },
            h("span", { class: `chip st-${c.status}` }, statusLabel(c.status)),
            h("span", { class: `age${c.overdue ? " late" : ""}` }, c.overdue ? `Vencido · ${Math.floor(c.ageDays)} días` : relativeTime(c.firstReportedAt, now)),
          ),
        ),
      ),
    ),
  );
}
