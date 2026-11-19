// "Estadísticas" page: repair times, most frequent problems, weekly flow, deadlines, zones.
// Charts are plain HTML/SVG (no library). Every chart has a hover tooltip and a table view.

import { h } from "./dom.js";
import { formatDays } from "./format.js";
import { SEVERITY_LABELS } from "../domain/schema.js";
import {
  byZone,
  casesInPeriod,
  frequencyByCategory,
  headline,
  repairTimeByCategory,
  slaBySeverity,
  weeklyFlow,
} from "../domain/stats.js";

const SVG_NS = "http://www.w3.org/2000/svg";
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

function card(title, subtitle, body, table) {
  return h(
    "article",
    { class: "stat-card" },
    h("h3", {}, title),
    subtitle ? h("p", { class: "stat-sub" }, subtitle) : null,
    body,
    table ? h("details", { class: "stat-table" }, h("summary", {}, "Ver tabla"), table) : null,
  );
}

function table(headers, rows) {
  return h(
    "div",
    { class: "table-scroll" },
    h(
      "table",
      {},
      h("thead", {}, h("tr", {}, headers.map((x) => h("th", { scope: "col" }, x)))),
      h("tbody", {}, rows.map((r) => h("tr", {}, r.map((x, i) => (i === 0 ? h("th", { scope: "row" }, x) : h("td", {}, x)))))),
    ),
  );
}

const empty = (text) => h("p", { class: "stat-empty" }, text);

function hbar({ label, value, max, valueText, note, tip }) {
  // The longest bar takes 78% of the track so its value label always fits after it.
  const width = max > 0 ? Math.max(0.5, (value / max) * 78) : 0;
  return h(
    "div",
    { class: "hbar" },
    h("span", { class: "hbar-label" }, label, note ? h("small", {}, note) : null),
    h(
      "span",
      { class: "hbar-track" },
      h("span", { class: "hbar-fill s-1", style: { width: `${width}%` }, tabindex: "0", "data-tip": tip }),
      h("span", { class: "hbar-value" }, valueText),
    ),
  );
}

function repairTimeChart(rows) {
  if (rows.length === 0) return card("¿Cuánto se tarda en reparar cada problema?", null, empty("Todavía no hay casos reparados y verificados en este periodo."));
  const max = Math.max(...rows.map((r) => r.medianDays));
  return card(
    "¿Cuánto se tarda en reparar cada problema?",
    "Mediana de días desde el primer reporte hasta la foto de después verificada.",
    h(
      "div",
      { class: "hbars" },
      rows.map((r) =>
        hbar({
          label: r.label,
          note: `${r.n} ${r.n === 1 ? "caso" : "casos"}`,
          value: r.medianDays,
          max,
          valueText: formatDays(r.medianDays),
          tip: `${r.label}: mediana ${formatDays(r.medianDays)}, promedio ${formatDays(r.avgDays)} (${r.n} casos reparados)`,
        }),
      ),
    ),
    table(
      ["Problema", "Casos reparados", "Mediana", "Promedio"],
      rows.map((r) => [r.label, String(r.n), formatDays(r.medianDays), formatDays(r.avgDays)]),
    ),
  );
}

const STACK = [
  ["fixed", "Reparados", "s-fixed"],
  ["open", "Abiertos", "s-open"],
  ["closed", "Cerrados sin reparar", "s-closed"],
];

function frequencyChart(rows) {
  if (rows.length === 0) return card("¿Qué problemas son más frecuentes?", null, empty("No hay casos en este periodo."));
  const max = Math.max(...rows.map((r) => r.total));
  return card(
    "¿Qué problemas son más frecuentes?",
    "Casos por tipo de problema. Un caso junta todos los reportes del mismo problema en el mismo lugar.",
    h(
      "div",
      {},
      h("div", { class: "legend-row" }, STACK.map(([, label, cls]) => h("span", {}, h("i", { class: `swatch ${cls}` }), label))),
      h(
        "div",
        { class: "hbars" },
        rows.map((r) =>
          h(
            "div",
            { class: "hbar" },
            h("span", { class: "hbar-label" }, r.label, h("small", {}, `${r.reports} reportes`)),
            h(
              "span",
              { class: "hbar-track" },
              h(
                "span",
                { class: "stack", style: { width: `${(r.total / max) * 85}%` } },
                STACK.filter(([key]) => r[key] > 0).map(([key, label, cls]) =>
                  h("span", {
                    class: `seg ${cls}`,
                    style: { "flex-grow": String(r[key]) },
                    tabindex: "0",
                    "data-tip": `${r.label}: ${r[key]} ${label.toLowerCase()} de ${r.total}`,
                  }),
                ),
              ),
              h("span", { class: "hbar-value" }, String(r.total)),
            ),
          ),
        ),
      ),
    ),
    table(
      ["Problema", "Casos", "Reparados", "Abiertos", "Cerrados", "Reportes"],
      rows.map((r) => [r.label, String(r.total), String(r.fixed), String(r.open), String(r.closed), String(r.reports)]),
    ),
  );
}

function flowChart(rows) {
  const W = 640;
  const H = 230;
  const pad = { l: 34, r: 104, t: 12, b: 28 };
  const max = niceMax(Math.max(1, ...rows.flatMap((r) => [r.reported, r.fixed])));
  const x = (i) => pad.l + (i * (W - pad.l - pad.r)) / Math.max(1, rows.length - 1);
  const y = (v) => pad.t + (1 - v / max) * (H - pad.t - pad.b);
  const step = Number.isInteger(max / 5) ? max / 5 : max / 4;
  const ticks = Array.from({ length: Math.round(max / step) + 1 }, (_, i) => i * step);
  const series = [
    ["reported", "Casos nuevos", "s-open", "Nuevos"],
    ["fixed", "Reparados", "s-fixed", "Reparados"],
  ];

  const chart = svg(
    "svg",
    { viewBox: `0 0 ${W} ${H}`, class: "line-chart", role: "img", "aria-label": "Casos nuevos y reparados por semana" },
    ticks.map((t) =>
      svg(
        "g",
        {},
        svg("line", { x1: pad.l, x2: W - pad.r, y1: y(t), y2: y(t), class: "grid" }),
        svg("text", { x: pad.l - 6, y: y(t) + 4, class: "axis", "text-anchor": "end" }, Number.isInteger(t) ? String(t) : ""),
      ),
    ),
    rows.map((r, i) => svg("text", { x: x(i), y: H - 8, class: "axis", "text-anchor": "middle" }, weekFmt.format(new Date(r.weekStart)))),
    series.map(([key, , cls, short]) => {
      const last = rows.at(-1);
      const other = key === "fixed" ? last.reported : last.fixed;
      // Keep the two end labels apart when the lines end close together.
      const below = key === "fixed" ? last.fixed <= other : last.reported < other;
      return svg(
        "g",
        { class: cls },
        svg("polyline", { class: "line", points: rows.map((r, i) => `${x(i)},${y(r[key])}`).join(" ") }),
        rows.map((r, i) => svg("circle", { class: "dot", cx: x(i), cy: y(r[key]), r: 4 })),
        svg("text", { x: x(rows.length - 1) + 10, y: y(last[key]) + (below ? 14 : -4), class: "end-label" }, `${short}: ${last[key]}`),
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
        "data-tip": `Semana del ${weekFmt.format(new Date(r.weekStart))}: ${r.reported} casos nuevos, ${r.fixed} reparados`,
      }),
    ),
  );

  return card(
    "Casos nuevos y reparados por semana",
    "Últimas 8 semanas. Si la línea de nuevos va arriba de la de reparados, los pendientes crecen.",
    h(
      "div",
      {},
      h("div", { class: "legend-row" }, series.map(([, label, cls]) => h("span", {}, h("i", { class: `swatch ${cls}` }), label))),
      chart,
      h("p", { class: "stat-sub" }, "Esta gráfica muestra siempre las últimas 8 semanas, sin importar el periodo elegido."),
    ),
    table(
      ["Semana del", "Casos nuevos", "Reparados"],
      rows.map((r) => [weekFmt.format(new Date(r.weekStart)), String(r.reported), String(r.fixed)]),
    ),
  );
}

function slaChart(rows) {
  const withData = rows.filter((r) => r.fixed > 0);
  return card(
    "¿Se repara dentro del plazo?",
    "Porcentaje de casos reparados dentro del plazo propuesto para su gravedad.",
    withData.length === 0
      ? empty("Todavía no hay casos reparados en este periodo.")
      : h(
          "div",
          { class: "hbars" },
          rows.map((r) =>
            hbar({
              label: SEVERITY_LABELS[r.severity],
              note: `plazo ${r.slaDays} ${r.slaDays === 1 ? "día" : "días"}${
                r.openOverdue ? ` · ${r.openOverdue} ${r.openOverdue === 1 ? "abierto vencido" : "abiertos vencidos"}` : ""
              }`,
              value: r.pct ?? 0,
              max: 100,
              valueText: r.pct === undefined ? "sin datos" : `${pct.format(r.pct)} %`,
              tip: r.pct === undefined ? `${SEVERITY_LABELS[r.severity]}: sin casos reparados` : `${SEVERITY_LABELS[r.severity]}: ${r.within} de ${r.fixed} reparados en ${r.slaDays} días o menos`,
            }),
          ),
        ),
    table(
      ["Gravedad", "Plazo", "Reparados", "Dentro del plazo", "Abiertos vencidos"],
      rows.map((r) => [SEVERITY_LABELS[r.severity], `${r.slaDays} días`, String(r.fixed), r.pct === undefined ? "—" : `${r.within} (${pct.format(r.pct)} %)`, String(r.openOverdue)]),
    ),
  );
}

function zoneTable(rows) {
  return h(
    "article",
    { class: "stat-card wide" },
    h("h3", {}, "Por zona"),
    h("p", { class: "stat-sub" }, "Dónde se acumulan los problemas y cuánto se tarda en cada zona."),
    rows.length === 0
      ? empty("No hay casos en este periodo.")
      : table(
          ["Zona", "Abiertos", "Peligrosos abiertos", "Fuera de plazo", "Reparados", "Mediana de reparación"],
          rows.map((r) => [r.zone, String(r.open), String(r.dangerousOpen), String(r.overdue), String(r.fixed), formatDays(r.medianDaysToFix)]),
        ),
  );
}

function tiles(s) {
  const tile = (value, label) => h("div", { class: "kpi" }, h("b", {}, value), h("span", {}, label));
  return h(
    "div",
    { class: "kpis stat-kpis" },
    tile(String(s.total), "Casos en el periodo"),
    tile(String(s.open), "Siguen abiertos"),
    tile(String(s.fixed), "Reparados y verificados"),
    tile(formatDays(s.medianDaysToFix), "Tiempo mediano de reparación"),
    tile(s.withinSlaPct === undefined ? "—" : `${pct.format(s.withinSlaPct)} %`, "Reparados dentro del plazo"),
    tile(s.reopenPct === undefined ? "—" : `${pct.format(s.reopenPct)} %`, "Reparaciones que no pasaron la foto"),
  );
}

const PERIODS = [
  [30, "Últimos 30 días"],
  [90, "Últimos 90 días"],
  [0, "Todo"],
];

export function createStatsView(el, { isDemo }) {
  let period = 90;
  let lastCases = [];
  let lastNow = Date.now();

  const tooltip = h("div", { class: "chart-tip", role: "tooltip", hidden: true });
  const showTip = (target, x, y) => {
    tooltip.textContent = target.getAttribute("data-tip");
    tooltip.hidden = false;
    const r = el.getBoundingClientRect();
    tooltip.style.setProperty("left", `${Math.min(x - r.left + 12, r.width - 260)}px`);
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

  function render(cases = lastCases, now = lastNow) {
    lastCases = cases;
    lastNow = now;
    const inPeriod = casesInPeriod(cases, period, now);
    // The page re-renders on every refresh; keep open tables open.
    const openTables = [...el.querySelectorAll("details")].map((d) => d.open);
    const buttons = PERIODS.map(([days, label]) =>
      h("button", { type: "button", "aria-pressed": String(days === period), onClick: () => ((period = days), render()) }, label),
    );
    el.replaceChildren(
      h(
        "div",
        { class: "stats-head" },
        h("div", {}, h("h2", {}, "Estadísticas"), h("p", { class: "stat-sub" }, isDemo ? "Calculadas con los datos de ejemplo (sintéticos)." : "Calculadas con los casos del portal.")),
        h("div", { class: "segmented", role: "group", "aria-label": "Periodo" }, buttons),
      ),
      tiles(headline(inPeriod)),
      h(
        "div",
        { class: "stat-grid" },
        repairTimeChart(repairTimeByCategory(inPeriod)),
        frequencyChart(frequencyByCategory(inPeriod)),
        flowChart(weeklyFlow(cases, now, 8)),
        slaChart(slaBySeverity(inPeriod)),
        zoneTable(byZone(inPeriod)),
      ),
      tooltip,
    );
    el.querySelectorAll("details").forEach((d, i) => (d.open = openTables[i] ?? false));
  }

  return { render };
}
