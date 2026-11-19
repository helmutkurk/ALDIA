// "Estadísticas" page: KPIs with change vs. the previous period, weekly trend, repair time per
// problem, most frequent problems, deadlines and zones. Plain HTML/SVG charts with a hover
// tooltip; every chart can switch to a table.

import { h } from "./dom.js";
import { formatDays } from "./format.js";
import { kpiCard } from "./views.js";
import { SEVERITY_LABELS } from "../domain/schema.js";
import { delta } from "../domain/trends.js";
import {
  byZone,
  casesInPeriod,
  casesInWindow,
  frequencyByCategory,
  headline,
  repairTimeByCategory,
  slaBySeverity,
  weeklyFlow,
} from "../domain/stats.js";

const SVG_NS = "http://www.w3.org/2000/svg";
const DAY_MS = 86_400_000;
const pct = new Intl.NumberFormat("es-GT", { maximumFractionDigits: 0 });
const weekFmt = new Intl.DateTimeFormat("es-GT", { day: "numeric", month: "short", timeZone: "America/Guatemala" });

function svg(tag, attrs = {}, ...children) {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) if (v !== undefined) el.setAttribute(k, String(v));
  for (const c of children.flat()) if (c != null) el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  return el;
}

function niceMax(v) {
  if (v <= 4) return 4;
  const pow = 10 ** Math.floor(Math.log10(v));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * pow >= v) return m * pow;
  return 10 * pow;
}

function tableIcon() {
  return svg(
    "svg",
    { viewBox: "0 0 24 24", class: "icon", "aria-hidden": "true" },
    svg("path", { d: "M3 5h18v14H3zM3 10h18M3 15h18M9 5v14" }),
  );
}

function table(headers, rows) {
  return h(
    "div",
    { class: "table-scroll" },
    h(
      "table",
      { class: "data-table" },
      h("thead", {}, h("tr", {}, headers.map((x) => h("th", { scope: "col" }, x)))),
      h("tbody", {}, rows.map((r) => h("tr", {}, r.map((x, i) => (i === 0 ? h("th", { scope: "row" }, x) : h("td", {}, x)))))),
    ),
  );
}

/** A chart card whose body can switch to its table with the icon button in the corner. */
function card({ title, sub, legend, body, tableEl, wide, key, tables }) {
  const showTable = tables.has(key);
  const toggle =
    tableEl &&
    h(
      "button",
      {
        type: "button",
        class: "table-toggle",
        "aria-pressed": String(showTable),
        "aria-label": showTable ? "Ver gráfica" : "Ver tabla",
        title: showTable ? "Ver gráfica" : "Ver tabla",
        "data-table-key": key,
      },
      tableIcon(),
    );
  return h(
    "article",
    { class: `stat-card${wide ? " wide" : ""}` },
    h(
      "div",
      { class: "stat-head" },
      h("div", {}, h("h3", {}, title), sub ? h("p", { class: "stat-sub" }, sub) : null),
      h("div", { class: "stat-head-right", style: { display: "flex", "align-items": "center", gap: "12px" } }, legend ?? null, toggle ?? null),
    ),
    showTable && tableEl ? tableEl : body,
  );
}

const empty = (text) => h("p", { class: "stat-empty" }, text);
const legendRow = (items) => h("div", { class: "legend-row" }, items.map(([label, cls]) => h("span", {}, h("i", { class: `swatch ${cls}` }), label)));

function barRow({ label, note, value, max, valueText, tip }) {
  const width = max > 0 ? Math.max(1, (value / max) * 100) : 0;
  return h(
    "div",
    { class: "bar-row" },
    h("span", { class: "bar-label" }, label, note ? h("small", {}, ` · ${note}`) : null),
    h("span", { class: "bar-track" }, h("span", { class: "bar-fill", style: { width: `${width}%` }, tabindex: "0", "data-tip": tip })),
    h("span", { class: "bar-value" }, valueText),
  );
}

function repairCard(rows, tables) {
  const max = Math.max(0, ...rows.map((r) => r.medianDays));
  return card({
    key: "repair",
    tables,
    title: "Tiempo de reparación por problema",
    sub: "Mediana de días hasta la foto de después verificada",
    body:
      rows.length === 0
        ? empty("Todavía no hay casos reparados y verificados en este periodo.")
        : h(
            "div",
            { class: "bars" },
            rows.map((r) =>
              barRow({
                label: r.label,
                note: `${r.n}`,
                value: r.medianDays,
                max,
                valueText: formatDays(r.medianDays),
                tip: `${r.label}: mediana ${formatDays(r.medianDays)}, promedio ${formatDays(r.avgDays)} (${r.n} ${r.n === 1 ? "caso" : "casos"})`,
              }),
            ),
          ),
    tableEl: rows.length === 0 ? null : table(["Problema", "Reparados", "Mediana", "Promedio"], rows.map((r) => [r.label, String(r.n), formatDays(r.medianDays), formatDays(r.avgDays)])),
  });
}

const STACK = [
  ["fixed", "Reparados", "s-fixed"],
  ["open", "Abiertos", "s-open"],
  ["closed", "Cerrados", "s-closed"],
];

function frequencyCard(rows, tables) {
  const max = Math.max(1, ...rows.map((r) => r.total));
  return card({
    key: "freq",
    tables,
    title: "Problemas más frecuentes",
    sub: "Casos por tipo de problema",
    legend: legendRow(STACK.map(([, label, cls]) => [label, cls])),
    body:
      rows.length === 0
        ? empty("No hay casos en este periodo.")
        : h(
            "div",
            { class: "bars" },
            rows.map((r) =>
              h(
                "div",
                { class: "bar-row" },
                h("span", { class: "bar-label" }, r.label),
                h(
                  "span",
                  { class: "bar-track", style: { background: "transparent" } },
                  STACK.filter(([k]) => r[k] > 0).map(([k, label, cls]) =>
                    h("span", {
                      class: `seg ${cls}`,
                      style: { width: `${(r[k] / max) * 100}%` },
                      tabindex: "0",
                      "data-tip": `${r.label}: ${r[k]} ${label.toLowerCase()} de ${r.total} (${r.reports} ${r.reports === 1 ? "reporte" : "reportes"})`,
                    }),
                  ),
                ),
                h("span", { class: "bar-value" }, String(r.total)),
              ),
            ),
          ),
    tableEl:
      rows.length === 0
        ? null
        : table(
            ["Problema", "Casos", "Reparados", "Abiertos", "Cerrados", "Reportes"],
            rows.map((r) => [r.label, String(r.total), String(r.fixed), String(r.open), String(r.closed), String(r.reports)]),
          ),
  });
}

function flowCard(rows, tables) {
  const W = 1000;
  const H = 240;
  const pad = { l: 40, r: 110, t: 14, b: 30 };
  const max = niceMax(Math.max(1, ...rows.flatMap((r) => [r.reported, r.fixed])));
  const x = (i) => pad.l + (i * (W - pad.l - pad.r)) / Math.max(1, rows.length - 1);
  const y = (v) => pad.t + (1 - v / max) * (H - pad.t - pad.b);
  const step = Number.isInteger(max / 5) ? max / 5 : max / 4;
  const ticks = Array.from({ length: Math.round(max / step) + 1 }, (_, i) => i * step);
  const series = [
    ["reported", "nuevos", "s-open"],
    ["fixed", "reparados", "s-fixed"],
  ];
  const last = rows.at(-1);
  const pts = (key) => rows.map((r, i) => `${x(i).toFixed(1)},${y(r[key]).toFixed(1)}`);

  const chart = svg(
    "svg",
    { viewBox: `0 0 ${W} ${H}`, class: "line-chart", role: "img", "aria-label": "Casos nuevos y reparados por semana" },
    ticks.map((t) =>
      svg(
        "g",
        {},
        svg("line", { x1: pad.l, x2: W - pad.r, y1: y(t), y2: y(t), class: "grid" }),
        svg("text", { x: pad.l - 8, y: y(t) + 4, class: "axis", "text-anchor": "end" }, String(t)),
      ),
    ),
    rows.map((r, i) => svg("text", { x: x(i), y: H - 8, class: "axis", "text-anchor": "middle" }, weekFmt.format(new Date(r.weekStart)))),
    svg("g", { class: "s-open" }, svg("path", { class: "area", d: `M${x(0)},${y(0)} L${pts("reported").join(" L")} L${x(rows.length - 1)},${y(0)} Z` })),
    series.map(([key, label, cls]) => {
      const other = key === "fixed" ? last.reported : last.fixed;
      const below = key === "fixed" ? last.fixed <= other : last.reported < other;
      return svg(
        "g",
        { class: cls },
        svg("polyline", { class: "line", points: pts(key).join(" ") }),
        svg("circle", { class: "dot", cx: x(rows.length - 1), cy: y(last[key]), r: 4.5 }),
        svg("text", { x: x(rows.length - 1) + 12, y: y(last[key]) + (below ? 14 : -2), class: "end-label" }, `${last[key]} ${label}`),
      );
    }),
    rows.map((r, i) =>
      svg("rect", {
        class: "hit",
        x: x(i) - (W - pad.l - pad.r) / (2 * Math.max(1, rows.length - 1)),
        y: pad.t,
        width: (W - pad.l - pad.r) / Math.max(1, rows.length - 1),
        height: H - pad.t - pad.b,
        tabindex: "0",
        "data-tip": `Semana del ${weekFmt.format(new Date(r.weekStart))}: ${r.reported} nuevos, ${r.fixed} reparados`,
      }),
    ),
  );

  return card({
    key: "flow",
    tables,
    wide: true,
    title: "Casos nuevos y reparados por semana",
    sub: "Últimas 8 semanas. Si la línea de nuevos va arriba, los pendientes crecen.",
    legend: legendRow([
      ["Nuevos", "s-open"],
      ["Reparados", "s-fixed"],
    ]),
    body: chart,
    tableEl: table(["Semana del", "Nuevos", "Reparados"], rows.map((r) => [weekFmt.format(new Date(r.weekStart)), String(r.reported), String(r.fixed)])),
  });
}

function slaCard(rows, tables) {
  const fills = { minor: "var(--series-fixed)", damages_cars: "var(--series-open)", dangerous: "var(--bad)" };
  return card({
    key: "sla",
    tables,
    title: "Reparado dentro del plazo",
    sub: "Por gravedad, con el plazo propuesto",
    body:
      rows.every((r) => r.fixed === 0)
        ? empty("Todavía no hay casos reparados en este periodo.")
        : h(
            "div",
            { class: "bars", style: { gap: "16px" } },
            rows.map((r) =>
              h(
                "div",
                { class: "progress" },
                h(
                  "div",
                  { class: "progress-top" },
                  h("span", {}, h("b", {}, SEVERITY_LABELS[r.severity]), ` · plazo ${r.slaDays} ${r.slaDays === 1 ? "día" : "días"}`),
                  h("b", {}, r.pct === undefined ? "—" : `${pct.format(r.pct)} %`),
                ),
                h(
                  "div",
                  { class: "progress-track" },
                  h("div", {
                    class: "progress-fill",
                    style: { width: `${Math.max(r.pct ?? 0, 1.5)}%`, background: fills[r.severity] },
                    tabindex: "0",
                    "data-tip": r.pct === undefined ? "Sin casos reparados" : `${r.within} de ${r.fixed} reparados en ${r.slaDays} días o menos`,
                  }),
                ),
                h(
                  "small",
                  {},
                  r.fixed === 0 ? "Sin casos reparados" : `${r.within} de ${r.fixed} a tiempo`,
                  r.openOverdue ? ` · ${r.openOverdue} ${r.openOverdue === 1 ? "abierto vencido" : "abiertos vencidos"}` : "",
                ),
              ),
            ),
          ),
    tableEl: table(
      ["Gravedad", "Plazo", "Reparados", "A tiempo", "Abiertos vencidos"],
      rows.map((r) => [SEVERITY_LABELS[r.severity], `${r.slaDays} días`, String(r.fixed), r.pct === undefined ? "—" : `${r.within} (${pct.format(r.pct)} %)`, String(r.openOverdue)]),
    ),
  });
}

function zoneCard(rows) {
  return h(
    "article",
    { class: "stat-card" },
    h("div", { class: "stat-head" }, h("div", {}, h("h3", {}, "Por zona"), h("p", { class: "stat-sub" }, "Dónde se acumulan los problemas"))),
    rows.length === 0
      ? empty("No hay casos en este periodo.")
      : table(
          ["Zona", "Abiertos", "Peligrosos", "Vencidos", "Reparados", "Mediana"],
          rows.map((r) => [r.zone, String(r.open), String(r.dangerousOpen), String(r.overdue), String(r.fixed), formatDays(r.medianDaysToFix)]),
        ),
  );
}

const PERIODS = [
  [30, "30 días"],
  [90, "90 días"],
  [0, "Todo"],
];

export function createStatsView(el, { isDemo }) {
  let period = 30;
  let lastCases = [];
  let lastNow = Date.now();
  const tables = new Set();

  const tooltip = h("div", { class: "chart-tip", role: "tooltip", hidden: true });
  const showTip = (target, x, y) => {
    tooltip.textContent = target.getAttribute("data-tip");
    tooltip.hidden = false;
    const r = el.getBoundingClientRect();
    tooltip.style.setProperty("left", `${Math.min(x - r.left + 12, r.width - 270)}px`);
    tooltip.style.setProperty("top", `${y - r.top + 14}px`);
  };
  el.addEventListener("pointermove", (e) => {
    const t = e.target instanceof Element ? e.target.closest("[data-tip]") : null;
    if (t) showTip(t, e.clientX, e.clientY);
    else tooltip.hidden = true;
  });
  el.addEventListener("pointerleave", () => (tooltip.hidden = true));
  el.addEventListener("focusin", (e) => {
    const t = e.target instanceof Element ? e.target.closest("[data-tip]") : null;
    if (!t) return;
    const b = t.getBoundingClientRect();
    showTip(t, b.left, b.bottom);
  });
  el.addEventListener("focusout", () => (tooltip.hidden = true));
  el.addEventListener("click", (e) => {
    const btn = e.target instanceof Element ? e.target.closest("[data-table-key]") : null;
    if (!btn) return;
    const key = btn.getAttribute("data-table-key");
    if (tables.has(key)) tables.delete(key);
    else tables.add(key);
    render();
  });

  function kpis(cases, now) {
    const current = casesInPeriod(cases, period, now);
    const cur = headline(current);
    const prev = period ? headline(casesInWindow(cases, now - 2 * period * DAY_MS, now - period * DAY_MS)) : undefined;
    const versus = `vs. los ${period} días anteriores`;
    const d = (a, b, opts) => (prev ? delta(a, b, opts) : { text: undefined, tone: "neutral" });
    return h(
      "section",
      { class: "kpi-grid", "aria-label": "Resumen" },
      kpiCard("Tiempo mediano de reparación", formatDays(cur.medianDaysToFix), d(cur.medianDaysToFix, prev?.medianDaysToFix, { unit: " d", digits: 1 }), versus),
      kpiCard(
        "Reparados dentro del plazo",
        cur.withinSlaPct === undefined ? "—" : `${pct.format(cur.withinSlaPct)} %`,
        d(cur.withinSlaPct, prev?.withinSlaPct, { unit: " pts", lowerIsBetter: false }),
        versus,
      ),
      kpiCard(
        "Reparaciones que no pasaron la foto",
        cur.reopenPct === undefined ? "—" : `${pct.format(cur.reopenPct)} %`,
        d(cur.reopenPct, prev?.reopenPct, { unit: " pts" }),
        versus,
      ),
      kpiCard("Casos nuevos", String(cur.total), d(cur.total, prev?.total), versus),
    );
  }

  function render(cases = lastCases, now = lastNow) {
    lastCases = cases;
    lastNow = now;
    const inPeriod = casesInPeriod(cases, period, now);
    const buttons = PERIODS.map(([days, label]) =>
      h("button", { type: "button", "aria-pressed": String(days === period), onClick: () => ((period = days), render()) }, label),
    );
    el.replaceChildren(
      h(
        "div",
        { class: "stats-filters" },
        h("div", { class: "segmented", role: "group", "aria-label": "Periodo" }, buttons),
        h("span", { class: "muted" }, isDemo ? "Calculadas con datos de ejemplo" : "Calculadas con los casos del portal"),
      ),
      kpis(cases, now),
      flowCard(weeklyFlow(cases, now, 8), tables),
      h(
        "div",
        { class: "stat-grid" },
        repairCard(repairTimeByCategory(inPeriod), tables),
        frequencyCard(frequencyByCategory(inPeriod), tables),
        slaCard(slaBySeverity(inPeriod), tables),
        zoneCard(byZone(inPeriod)),
      ),
      tooltip,
    );
  }

  return { render };
}
