import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES, t } from './i18n.js';
import { element } from './panel.js';

/** Read-only dashboard for exactly the map's area and filters, including CSV export.
 * @param {HTMLElement} root
 * @param {{api: ReturnType<import('./api.js').createApiClient>, filters: import('./api.js').ReportQuery}} options
 */
export function createDashboard(root, { api, filters }) {
  let controller;
  let generation = 0;
  const back = element('a', 'back-link', t.backToMap);
  back.href = '#/';
  const title = element('h1', '', t.dashboard);
  title.tabIndex = -1;
  const scope = element('p', 'muted', t.dashboardScope);
  /** @param {string} heading @param {{id: string, label: string}[]} entries @param {Object<string, number>} counts @param {number} total */
  function bars(heading, entries, counts, total) {
    const section = element('section', 'bar-section');
    section.append(element('h2', '', heading));
    const list = element('ul', 'bar-list');
    for (const { id, label } of entries) {
      const count = counts[id] ?? 0;
      const row = element('li');
      const text = element('span', 'bar-label', `${label}: ${count}`);
      const bar = document.createElement('meter');
      bar.min = 0;
      bar.max = Math.max(total, 1);
      bar.value = count;
      bar.setAttribute('aria-label', `${label}: ${count}`);
      bar.textContent = String(count);
      row.append(text, bar);
      list.append(row);
    }
    section.append(list);
    return section;
  }
  async function load() {
    controller?.abort();
    controller = new AbortController();
    const current = ++generation;
    const loading = element('p', '', t.dashboardLoading);
    loading.setAttribute('role', 'status');
    root.replaceChildren(back, title, scope, loading);
    root.setAttribute('aria-busy', 'true');
    try {
      const stats = await api.getStats(filters, { signal: controller.signal });
      if (current !== generation) return;
      const csv = element('a', 'csv-link', t.downloadCsv);
      csv.href = api.getCsvUrl(filters);
      csv.download = 'reportes.csv';
      root.replaceChildren(
        back,
        title,
        scope,
        element('p', 'dashboard-total', t.totalReports(stats.total)),
        csv,
        bars(t.byCategory, CATEGORIES, stats.by_category, stats.total),
        bars(
          t.byStatus,
          STATUSES.map((id) => ({ id, label: t.statuses[id] })),
          stats.by_status,
          stats.total,
        ),
        bars(
          t.byResolution,
          RESOLUTIONS.map((id) => ({ id, label: t.resolutions[id] })),
          stats.by_resolution,
          stats.total,
        ),
      );
      title.focus({ preventScroll: true });
    } catch (error) {
      if (current !== generation || error.name === 'AbortError') return;
      const message = element('p', 'error-message', t.dashboardError);
      message.setAttribute('role', 'alert');
      const retry = element('button', 'retry-button', t.retry);
      retry.type = 'button';
      retry.addEventListener('click', load);
      root.replaceChildren(back, title, scope, message, retry);
    } finally {
      if (current === generation) root.setAttribute('aria-busy', 'false');
    }
  }
  load();
  return {
    destroy() {
      generation++;
      controller?.abort();
      root.replaceChildren();
      root.removeAttribute('aria-busy');
    },
  };
}
