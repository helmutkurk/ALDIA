import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES, t, ui } from './i18n.js';
import { element } from './dom.js';
import { filtersHash } from './filters.js';
import { categoryTable } from './dashboard-distribution.js';
import { createCsvExport } from './csv-export.js';
import {
  agesCard,
  frequencyCard,
  kpiCards,
  repairCard,
  timesCard,
  trendCard,
} from './dashboard-panel.js';

const groups = Object.keys(t.dash.groups);
const PERIODS = Object.freeze([
  { id: '30', days: 30 },
  { id: '90', days: 90 },
  { id: 'all', days: 0 },
]);

/** Today's date in the municipality's timezone (not the staff device timezone). */
export function guatemalaToday(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Guatemala',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const part = (type) => parts.find((item) => item.type === type).value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
const shift = (day, delta) => {
  const date = new Date(`${day}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + delta);
  return date.toISOString().slice(0, 10);
};
/** Inclusive window of `days` calendar days ending today, and the same-length window before it. */
export function periodDates(days, now = new Date()) {
  const end = guatemalaToday(now);
  const start = shift(end, -(days - 1));
  return {
    current: { created_from: start, created_to: end },
    previous: {
      created_from: shift(start, -days),
      created_to: shift(start, -1),
    },
  };
}

/** Filtered municipal statistics (mockup "Panel2"). Calculations stay on the API.
 * Filters with their own dates are kept as they are; otherwise the period buttons decide.
 * @param {HTMLElement} root
 * @param {{api: ReturnType<import('./api.js').createApiClient>, filters: import('./api.js').ReportQuery, now?: () => Date}} options
 */
export function createDashboard(
  root,
  { api, filters, now = () => new Date() },
) {
  const custom = Boolean(filters.created_from || filters.created_to);
  const base = { ...filters };
  delete base.include_old;
  if (!custom) {
    delete base.created_from;
    delete base.created_to;
  }
  let period = custom ? 'custom' : '30';
  let controller;
  let generation = 0;
  let csvExport;
  const visibleGroups = filters.state_group ? [filters.state_group] : groups;
  root.classList.add('page--dashboard');

  /** Request scope for the selected period, and the previous one for the change figures. */
  function scopes() {
    if (period === 'custom') return { current: { ...filters }, previous: null };
    if (period === 'all')
      return { current: { ...base, include_old: true }, previous: null };
    const days = PERIODS.find((item) => item.id === period).days;
    const dates = periodDates(days, now());
    return {
      current: { ...base, ...dates.current, include_old: true },
      previous: { ...base, ...dates.previous, include_old: true },
    };
  }

  const back = element('a', 'back-link', t.backToMap);
  back.href = filtersHash('#/', filters);
  const title = element('h1', '', ui.stats.title);
  title.tabIndex = -1;
  const scope = element('p', 'dash-scope', ui.stats.scope);
  const titles = element('div', 'dash-titles');
  titles.append(back, title, scope);
  const tools = element('div', 'dash-tools');
  const periodGroup = element('div', 'stat-periods');
  periodGroup.setAttribute('role', 'group');
  periodGroup.setAttribute('aria-label', ui.stats.period);
  const periodButtons = PERIODS.map(({ id }) => {
    const button = element('button', '', ui.stats.periods[id]);
    button.type = 'button';
    button.addEventListener('click', () => {
      if (period === id) return;
      period = id;
      load();
    });
    periodGroup.append(button);
    return { id, button };
  });
  const exportSlot = element('div', 'dash-export');
  tools.append(periodGroup, exportSlot);
  const band = element('div', 'dash-band');
  band.append(titles, tools);
  const body = element('div', 'dash-body');

  /** Every link uses the same scope and replaces only its named dimension. */
  function listLink(text, patch = {}) {
    const link = element('a', '', text);
    link.href = filtersHash('#/', { ...filters, ...patch, offset: 0 });
    return link;
  }
  /** Legacy (v0.1) API: plain count bars. */
  function bars(heading, entries, counts, total, dimension) {
    const section = element('section', 'bar-section');
    section.append(element('h2', '', heading));
    const list = element('ul', 'bar-list');
    for (const { id, label } of entries) {
      const value = counts[id] ?? 0;
      const row = element('li');
      const link = listLink(`${label}: ${value}`, { [dimension]: id });
      link.className = 'bar-label';
      const meter = document.createElement('meter');
      meter.min = 0;
      meter.max = Math.max(total, 1);
      meter.value = value;
      meter.setAttribute('aria-label', `${label}: ${value}`);
      meter.textContent = String(value);
      row.append(link, meter);
      list.append(row);
    }
    section.append(list);
    return section;
  }

  function crossTab(stats, signal, isCurrent, requestScope) {
    const card = element('article', 'stat-card stat-cross');
    const head = element('div', 'stat-card-head');
    const heading = element('div');
    heading.append(
      element('h2', '', ui.stats.crossTitle),
      element('p', 'stat-card-sub', ui.stats.crossSub),
    );
    head.append(heading);
    const details = element('details', 'category-group-detail');
    const cross = element('div');
    details.append(element('summary', '', t.dash.seeTable), cross);
    card.append(
      head,
      details,
      element('p', 'muted stat-zone-note', t.dash.zoneLimits),
    );
    let loaded = false;
    async function loadRows() {
      const categories = requestScope.category
        ? CATEGORIES.filter(({ id }) => id === requestScope.category)
        : CATEGORIES;
      try {
        const rows = await Promise.all(
          categories.map(async (category) => ({
            category,
            stats: requestScope.category
              ? stats
              : await api.getStats(
                  { ...requestScope, category: category.id },
                  { signal },
                ),
          })),
        );
        if (!isCurrent()) return;
        cross.replaceChildren(categoryTable(rows, visibleGroups, listLink));
      } catch (error) {
        if (!isCurrent() || error.name === 'AbortError') return;
        const retry = element('button', 'retry-button', t.retry);
        retry.type = 'button';
        retry.addEventListener('click', loadRows);
        cross.replaceChildren(
          element('p', 'error-message', t.dash.crossError),
          retry,
        );
      }
    }
    details.addEventListener('toggle', () => {
      if (isCurrent() && details.open && !loaded) {
        loaded = true;
        loadRows();
      }
    });
    return card;
  }

  async function load() {
    controller?.abort();
    controller = new AbortController();
    const { signal } = controller;
    const current = ++generation;
    const isCurrent = () => current === generation;
    for (const { id, button } of periodButtons)
      button.setAttribute('aria-pressed', String(id === period));
    const { current: requestScope, previous: previousScope } = scopes();
    csvExport?.destroy();
    csvExport = createCsvExport({ api, filters: requestScope });
    exportSlot.replaceChildren(csvExport.render({ signal, isCurrent }));
    const loading = element('p', '', t.dashboardLoading);
    loading.setAttribute('role', 'status');
    body.replaceChildren(loading);
    root.replaceChildren(band, body);
    root.setAttribute('aria-busy', 'true');
    try {
      const [stats, previous] = await Promise.all([
        api.getStats(requestScope, { signal }),
        previousScope
          ? api.getStats(previousScope, { signal }).catch((error) => {
              if (error.name === 'AbortError') throw error;
              return null; // Change figures are optional; the page still renders.
            })
          : Promise.resolve(null),
      ]);
      if (!isCurrent()) return;
      const total = element(
        'p',
        'dashboard-total',
        t.totalReports(stats.total),
      );
      if (stats.recibidos === undefined) {
        body.replaceChildren(
          total,
          bars(
            t.byCategory,
            CATEGORIES,
            stats.by_category,
            stats.total,
            'category',
          ),
          bars(
            t.byStatus,
            STATUSES.map((id) => ({ id, label: t.statuses[id] })),
            stats.by_status,
            stats.total,
            'status',
          ),
          bars(
            t.byResolution,
            RESOLUTIONS.map((id) => ({ id, label: t.resolutions[id] })),
            stats.by_resolution,
            stats.total,
            'resolution',
          ),
        );
      } else {
        total.classList.add('sr-only');
        const grid = element('section', 'stat-grid-cards');
        grid.append(
          repairCard(stats.por_categoria),
          frequencyCard(stats.por_categoria ?? fromTop(stats), listLink),
          agesCard(stats.antiguedad_abiertos),
          timesCard(stats),
          crossTab(stats, signal, isCurrent, requestScope),
        );
        body.replaceChildren(
          total,
          kpiCards(stats, previous, Boolean(previousScope)),
          trendCard(stats),
          grid,
          element('p', 'stat-note', t.dash.metricsNote),
        );
      }
      title.focus({ preventScroll: true });
    } catch (error) {
      if (!isCurrent() || error.name === 'AbortError') return;
      const message = element('p', 'error-message', t.dashboardError);
      message.setAttribute('role', 'alert');
      const retry = element('button', 'retry-button', t.retry);
      retry.type = 'button';
      retry.addEventListener('click', load);
      body.replaceChildren(message, retry);
      root.replaceChildren(band, body);
    } finally {
      if (isCurrent()) root.setAttribute('aria-busy', 'false');
    }
  }
  load();
  return {
    destroy() {
      generation++;
      controller?.abort();
      csvExport?.destroy();
      root.replaceChildren();
      root.classList.remove('page--dashboard');
      root.removeAttribute('aria-busy');
    },
  };
}

/** Older v0.2 responses have no per-category states: show totals only. */
function fromTop(stats) {
  return Object.entries(stats.by_category ?? {}).map(([category, total]) => ({
    category,
    total,
  }));
}
