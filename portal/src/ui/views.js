// KPI cards, filter bar, map legend and the work queue.

import { h } from "./dom.js";
import { formatDays, relativeTime } from "./format.js";
import { CATEGORIES, categoryLabel } from "../domain/categories.js";
import { STATUSES, statusLabel } from "../domain/statuses.js";
import { delta, sparklinePoints } from "../domain/trends.js";

const SVG_NS = "http://www.w3.org/2000/svg";

function sparkline(series) {
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", "0 0 88 28");
  svg.setAttribute("class", "kpi-spark");
  svg.setAttribute("aria-hidden", "true");
  const points = sparklinePoints(series);
  if (points) {
    const line = document.createElementNS(SVG_NS, "polyline");
    line.setAttribute("points", points);
    svg.append(line);
  }
  return svg;
}

function chevron() {
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", "chev");
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML = '<path d="m6 9 6 6 6-6" fill="none" stroke="currentColor"/>';
  return svg;
}

/** One KPI card: label, value, trend line and change vs. the previous period. */
export function kpiCard(label, valueText, d, versus, series) {
  return h(
    "article",
    { class: "kpi" },
    h("span", { class: "kpi-label" }, label),
    h("div", { class: "kpi-row" }, h("span", { class: "kpi-value" }, valueText), series ? sparkline(series) : null),
    h(
      "span",
      { class: "kpi-delta" },
      d.text ? h("b", { class: `tone-${d.tone}` }, d.text) : "Sin datos previos",
      d.text ? ` ${versus}` : "",
    ),
  );
}

export function renderKpis(el, t) {
  el.replaceChildren(
    kpiCard("Casos abiertos", String(t.open.value), delta(t.open.value, t.open.previous), t.open.versus, t.open.series),
    kpiCard("Reportes nuevos (24 h)", String(t.newReports.value), delta(t.newReports.value, t.newReports.previous), t.newReports.versus, t.newReports.series),
    kpiCard("Peligrosos sin atender", String(t.dangerous.value), delta(t.dangerous.value, t.dangerous.previous), t.dangerous.versus, t.dangerous.series),
    kpiCard(
      "Tiempo medio de reparación",
      formatDays(t.repairDays.value),
      delta(t.repairDays.value, t.repairDays.previous, { unit: " d", digits: 1 }),
      t.repairDays.versus,
      t.repairDays.series,
    ),
  );
}

/** A dropdown made of <details>; closes when another opens or on outside click. */
export function dropdown(key, valueEl, content) {
  return h("details", { class: "dropdown menu" }, h("summary", {}, h("span", { class: "k" }, key), valueEl, chevron()), content);
}

export function closeMenusOnOutsideClick() {
  document.addEventListener("click", (e) => {
    for (const d of document.querySelectorAll("details.menu[open]")) {
      if (!d.contains(e.target)) d.removeAttribute("open");
    }
  });
}

export function createFilters(el, searchInput, initial, onChange) {
  let f = { ...initial, categories: [...initial.categories] };
  const emit = () => onChange({ ...f, categories: [...f.categories] });

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

  const categoryValue = h("span", { class: "v" }, "Todas");
  const updateCategoryValue = () => {
    categoryValue.textContent =
      f.categories.length === 0 ? "Todas" : f.categories.length === 1 ? categoryLabel(f.categories[0]) : `${f.categories.length} tipos`;
  };
  const categoryList = h(
    "div",
    { class: "menu-list left" },
    CATEGORIES.map((c) => {
      const box = h("input", { type: "checkbox", value: c.id });
      box.addEventListener("change", () => {
        f.categories = box.checked ? [...f.categories, c.id] : f.categories.filter((x) => x !== c.id);
        updateCategoryValue();
        emit();
      });
      return h("label", {}, box, c.label);
    }),
  );

  const periods = [
    [0, "Todo"],
    [7, "7 días"],
    [30, "30 días"],
  ];
  const periodValue = h("span", { class: "v" }, "Todo");
  const periodMenu = dropdown("Periodo", periodValue, h("div", { class: "menu-list left" }));
  periodMenu.querySelector(".menu-list").append(
    ...periods.map(([days, label]) => {
      const btn = h("button", { type: "button" }, h("b", {}, label));
      btn.addEventListener("click", () => {
        f.periodDays = days;
        periodValue.textContent = label;
        periodMenu.removeAttribute("open");
        emit();
      });
      return btn;
    }),
  );

  const urgent = h("input", { type: "checkbox", id: "filter-urgent" });
  urgent.addEventListener("change", () => {
    f.urgentOnly = urgent.checked;
    emit();
  });

  searchInput.addEventListener("input", () => {
    f.text = searchInput.value.slice(0, 80);
    emit();
  });

  el.replaceChildren(
    h("div", { class: "segmented", role: "group", "aria-label": "Estado" }, viewButtons),
    dropdown("Categoría", categoryValue, categoryList),
    periodMenu,
    h("label", { class: "check" }, urgent, "Solo urgentes o vencidos"),
  );
}

export function renderLegend(el) {
  const shown = ["new", "in_review", "scheduled", "in_progress", "fix_claimed", "reopened", "fixed"];
  el.replaceChildren(
    ...shown.map((s) => h("span", { class: "legend-item" }, h("i", { class: `dot st-${s}` }), s === "fix_claimed" ? "Falta foto" : STATUSES[s].label)),
  );
}

export function priorityLevel(c) {
  if (!c.open) return null;
  if (c.priority >= 70) return { label: "Alta", cls: "high" };
  if (c.priority >= 45) return { label: "Media", cls: "mid" };
  return { label: "Baja", cls: "" };
}

export function renderQueue(listEl, countEl, cases, { selectedId, now, onSelect }) {
  const open = cases.filter((c) => c.open).length;
  countEl.textContent = open === cases.length ? `${cases.length} ${cases.length === 1 ? "caso" : "casos"}` : `${cases.length} casos · ${open} abiertos`;
  if (cases.length === 0) {
    listEl.replaceChildren(h("li", { class: "empty" }, "No hay casos con estos filtros."));
    return;
  }
  listEl.replaceChildren(
    ...cases.slice(0, 300).map((c) => {
      const level = priorityLevel(c);
      return h(
        "li",
        {},
        h(
          "button",
          {
            type: "button",
            class: `case-row${c.id === selectedId ? " is-selected" : ""}`,
            onClick: () => onSelect(c.id),
            "aria-label": `${categoryLabel(c.category)}, ${c.address ?? c.id}, ${statusLabel(c.status)}`,
          },
          h("i", { class: `dot st-${c.status}`, title: statusLabel(c.status) }),
          h(
            "span",
            { class: "row-main" },
            h("span", { class: "row-title" }, categoryLabel(c.category)),
            h("span", { class: "row-sub" }, c.address ?? c.id),
          ),
          h(
            "span",
            { class: "row-meta" },
            level ? h("span", { class: `prio ${level.cls}` }, level.label) : h("span", { class: "prio" }, statusLabel(c.status)),
            h(
              "span",
              { class: `age${c.overdue ? " late" : ""}` },
              c.overdue ? `Vencido · ${Math.floor(c.ageDays)} d` : relativeTime(c.firstReportedAt, now),
            ),
          ),
        ),
      );
    }),
  );
}
