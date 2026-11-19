// ALDÍA government portal: wires the data source, the domain logic and the views together.

import { readConfig, TILE_PROVIDERS } from "./config.js";
import { createMockSource } from "./data/mock-source.js";
import { createApiSource } from "./data/api-source.js";
import { parseCase, parseCaseList } from "./domain/schema.js";
import { summarizeCase } from "./domain/cases.js";
import { applyFilters, DEFAULT_FILTERS, sortForQueue } from "./domain/filters.js";
import { kpiTrends } from "./domain/trends.js";
import { toGeoJSON, toOpen311 } from "./domain/exports.js";
import { categoryLabel } from "./domain/categories.js";
import { statusLabel } from "./domain/statuses.js";
import { createMapView } from "./ui/map-view.js";
import { closeMenusOnOutsideClick, createFilters, renderKpis, renderLegend, renderQueue } from "./ui/views.js";
import { renderDetail } from "./ui/detail-view.js";
import { createStatsView } from "./ui/stats-view.js";
import { downloadJson, h } from "./ui/dom.js";

const config = readConfig(location.search);
const source = config.source === "api" ? createApiSource({ baseUrl: config.apiBaseUrl }) : createMockSource();

const $ = (id) => document.getElementById(id);
const state = {
  cases: new Map(), // id -> parsed case
  filters: { ...DEFAULT_FILTERS },
  selectedId: null,
  lastSync: null,
  error: null,
  seenReports: null, // Set of report ids, null until the first load
};

$("municipality").textContent = config.municipality;
$("demo-badge").hidden = source.kind !== "mock";

const map = createMapView($("map"), {
  center: config.map.center,
  zoom: config.map.zoom,
  tiles: TILE_PROVIDERS[config.map.tiles],
  onSelect: select,
});
createFilters($("filters"), $("filter-search"), state.filters, (filters) => {
  state.filters = filters;
  render();
});
renderLegend($("legend"));
closeMenusOnOutsideClick();
const stats = createStatsView($("stats-view"), { isDemo: source.kind === "mock" });

/** Two pages, chosen by the URL hash: #mapa (default) and #estadisticas. */
const currentPage = () => (location.hash === "#estadisticas" ? "estadisticas" : "mapa");

function showPage() {
  const page = currentPage();
  for (const id of ["mapa", "estadisticas"]) {
    const tab = $(`tab-${id}`);
    if (id === page) tab.setAttribute("aria-current", "page");
    else tab.removeAttribute("aria-current");
  }
  const onStats = page === "estadisticas";
  $("page-title").textContent = onStats ? "Estadísticas" : "Mapa y casos";
  document.title = `ALDÍA · ${onStats ? "Estadísticas" : "Mapa y casos"}`;
  $("stats-view").hidden = !onStats;
  $("map-page").hidden = onStats;
  $("search-wrap").hidden = onStats;
  render();
  if (!onStats) requestAnimationFrame(() => map.resize());
}
window.addEventListener("hashchange", showPage);

function toast(text, tone = "") {
  const el = h("div", { class: `toast ${tone}` }, text);
  $("toasts").append(el);
  setTimeout(() => el.remove(), 6_000);
}

function noteNewReports(cases) {
  const ids = new Set(cases.flatMap((c) => c.reports.map((r) => r.id)));
  if (state.seenReports) {
    const fresh = cases.flatMap((c) => c.reports.filter((r) => !state.seenReports.has(r.id)).map(() => c));
    for (const c of fresh.slice(0, 3)) toast(`Nuevo reporte: ${categoryLabel(c.category)}, ${c.address ?? c.id}`);
  }
  state.seenReports = ids;
}

async function refresh() {
  try {
    const parsed = parseCaseList(await source.listCases());
    if (!parsed.ok) throw new Error("El servidor envió datos con un formato inesperado.");
    noteNewReports(parsed.value.cases);
    state.cases = new Map(parsed.value.cases.map((c) => [c.id, c]));
    state.lastSync = Date.now();
    state.error = parsed.value.rejected > 0 ? `${parsed.value.rejected} caso(s) con datos inválidos no se muestran.` : null;
  } catch (e) {
    state.error = e instanceof Error ? e.message : "No se pudieron cargar los casos.";
  }
  render();
}

function upsert(rawCase) {
  const parsed = parseCase(rawCase);
  if (parsed.ok) state.cases.set(parsed.value.id, parsed.value);
}

function select(id) {
  state.selectedId = id;
  render();
  const c = state.cases.get(id);
  if (c) map.focus(c);
}

async function changeStatus(id, status, note) {
  upsert(await source.setStatus(id, status, note));
  toast(`Estado actualizado: ${statusLabel(status)}`, "good");
  render();
}

async function simulate(id, passed) {
  upsert(await source.simulateRepairCheck(id, passed));
  toast(
    passed ? "La foto de después pasó la verificación: caso reparado." : "La foto de después muestra el problema: caso reabierto.",
    passed ? "good" : "warn",
  );
  render();
}

let visible = [];
let allSummaries = [];

function render() {
  const now = Date.now();
  allSummaries = [...state.cases.values()].map((c) => summarizeCase(c, now));

  if (currentPage() === "estadisticas") {
    stats.render(allSummaries, now);
    renderSyncStatus();
    return;
  }

  visible = sortForQueue(applyFilters(allSummaries, state.filters, now));
  renderKpis($("kpis"), kpiTrends(allSummaries, now));
  map.render(visible, state.selectedId);
  renderQueue($("case-list"), $("list-count"), visible, { selectedId: state.selectedId, now, onSelect: select });

  const selected = state.selectedId ? allSummaries.find((c) => c.id === state.selectedId) : undefined;
  $("list-view").hidden = Boolean(selected);
  $("detail-view").hidden = !selected;
  if (selected) {
    renderDetail($("detail-view"), selected, {
      now,
      onBack: () => select(null),
      onChangeStatus: changeStatus,
      onSimulate: source.supportsSimulation ? simulate : undefined,
      onExport: (c) => downloadJson(`aldia-${c.id}-open311.json`, [toOpen311(c, { agency: config.agency })]),
    });
  }
  renderSyncStatus();
}

function renderSyncStatus() {
  const el = $("sync");
  if (state.error) {
    el.textContent = state.error;
    el.className = "sync is-error";
  } else if (state.lastSync) {
    const s = Math.round((Date.now() - state.lastSync) / 1000);
    el.textContent = `En vivo · actualizado hace ${s} s`;
    el.className = "sync is-live";
  } else {
    el.textContent = "Cargando casos…";
    el.className = "sync";
  }
}

const exportCases = () => (currentPage() === "estadisticas" ? allSummaries : visible);
$("export-geojson").addEventListener("click", () => {
  downloadJson("aldia-casos.geojson", toGeoJSON(exportCases()));
  $("export-menu").removeAttribute("open");
});
$("export-open311").addEventListener("click", () => {
  downloadJson("aldia-casos-open311.json", exportCases().map((c) => toOpen311(c, { agency: config.agency })));
  $("export-menu").removeAttribute("open");
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && state.selectedId) select(null);
});
window.addEventListener("resize", () => map.resize());

refresh().then(showPage);
setInterval(refresh, config.pollMs);
setInterval(renderSyncStatus, 1_000);
