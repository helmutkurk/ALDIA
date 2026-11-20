import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES, t, staffError } from './i18n.js';
import { element } from './dom.js';
import { filtersHash } from './filters.js';
import { metricCards } from './dashboard-metrics.js';
import { allTimeSection, lastWeekSection } from './dashboard-trends.js';
import { categoryTable } from './dashboard-distribution.js';
import { recentActivity } from './dashboard-recent.js';
import { categoryCharts } from './category-charts.js';

const groups = Object.keys(t.dash.groups);
/** Filtered municipal statistics. Calculations stay on the API, never on a list page.
 * @param {HTMLElement} root
 * @param {{api: ReturnType<import('./api.js').createApiClient>, filters: import('./api.js').ReportQuery}} options
 */
export function createDashboard(root, { api, filters }) {
  // Without explicit dates the dashboard covers the full history, including old reports.
  filters = {
    ...filters,
    ...(!filters.created_from && !filters.created_to
      ? { include_old: true }
      : {}),
  };
  let controller;
  let generation = 0;
  let delimiter = 'comma';
  let csvObjectUrl;
  const revokeCsv = () => {
    if (csvObjectUrl) {
      URL.revokeObjectURL(csvObjectUrl);
      csvObjectUrl = null;
    }
  };
  const visibleGroups = filters.state_group ? [filters.state_group] : groups;
  root.classList.add('page--dashboard');
  const back = element('a', 'back-link', t.backToMap);
  back.href = filtersHash('#/', filters);
  const title = element('h1', '', t.dashboard);
  title.tabIndex = -1;
  const scope = element('p', 'dash-scope', t.dashboardScope);
  const band = element('div', 'dash-band');
  band.append(back, title, scope);
  const body = element('div', 'dash-body');
  /** Every link uses the same scope and replaces only its named dimension.
   * @param {string} text @param {object} patch
   */
  function listLink(text, patch = {}) {
    const link = element('a', '', text);
    link.href = filtersHash('#/', { ...filters, ...patch, offset: 0 });
    return link;
  }
  /** @param {string} heading @param {{id: string, label: string}[]} entries @param {Object<string, number>} counts @param {number} total @param {string} dimension */
  function bars(heading, entries, counts, total, dimension) {
    const section = element('section', 'bar-section');
    section.append(element('h2', '', heading));
    const list = element('ul', 'bar-list');
    for (const { id, label } of entries) {
      const count = counts[id] ?? 0;
      const row = element('li');
      const link = listLink(`${label}: ${count}`, { [dimension]: id });
      link.className = 'bar-label';
      const bar = document.createElement('meter');
      bar.min = 0;
      bar.max = Math.max(total, 1);
      bar.value = count;
      bar.setAttribute('aria-label', `${label}: ${count}`);
      bar.textContent = String(count);
      row.append(link, bar);
      list.append(row);
    }
    section.append(list);
    section.append(
      element(
        'p',
        'muted chart-note',
        dimension === 'category'
          ? 'Tipos de problemas con más reportes; ayuda a priorizar los recursos municipales.'
          : 'Cantidad de reportes en cada estado; permite ver dónde se acumula el trabajo.',
      ),
    );
    return section;
  }
  async function load() {
    controller?.abort();
    controller = new AbortController();
    const current = ++generation;
    const loading = element('p', '', t.dashboardLoading);
    loading.setAttribute('role', 'status');
    body.replaceChildren(loading);
    root.replaceChildren(band, body);
    root.setAttribute('aria-busy', 'true');
    try {
      const stats = await api.getStats(filters, { signal: controller.signal });
      if (current !== generation) return;
      const csv = element('a', 'csv-link', t.downloadCsv);
      const updateCsv = () => {
        csv.href = api.getCsvUrl({ ...filters, delimiter });
      };
      updateCsv();
      csv.download = 'reportes.csv';
      const csvStatus = element('p');
      csvStatus.setAttribute('role', 'status');
      if (api.getCsvBlob)
        csv.addEventListener('click', async (event) => {
          event.preventDefault();
          if (csv.getAttribute('aria-disabled') === 'true') return;
          csv.setAttribute('aria-disabled', 'true');
          csvStatus.textContent = t.dash.csvLoading;
          try {
            const blob = await api.getCsvBlob(
              { ...filters, delimiter },
              { signal: controller.signal },
            );
            if (current !== generation) return;
            revokeCsv();
            csvObjectUrl = URL.createObjectURL(blob);
            const download = element('a');
            download.href = csvObjectUrl;
            download.download = 'reportes.csv';
            root.append(download);
            download.click();
            download.remove();
            csvStatus.textContent = '';
          } catch (error) {
            if (current === generation && error.name !== 'AbortError')
              csvStatus.textContent = staffError(error);
          } finally {
            if (current === generation)
              csv.setAttribute('aria-disabled', 'false');
          }
        });
      const delimiterLabel = element('label', '', t.dash.delimiter);
      const delimiterSelect = document.createElement('select');
      delimiterSelect.setAttribute('aria-label', t.dash.delimiter);
      for (const id of ['comma', 'semicolon']) {
        const option = element('option', '', t.dash[id]);
        option.value = id;
        delimiterSelect.append(option);
      }
      delimiterSelect.value = delimiter;
      delimiterSelect.addEventListener('change', () => {
        delimiter = delimiterSelect.value;
        updateCsv();
      });
      delimiterLabel.append(delimiterSelect);
      const exportBox = element('section', 'export-box dash-block');
      exportBox.append(
        element('h2', '', t.dash.exportData),
        delimiterLabel,
        csv,
        csvStatus,
      );
      body.replaceChildren(
        element('p', 'dashboard-total', t.totalReports(stats.total)),
      );
      root.replaceChildren(band, body);
      if (stats.recibidos === undefined) {
        body.append(exportBox);
        body.append(
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
        const zone = element('section', 'zone-box dash-block');
        const change = element('a', 'zone-link', t.dash.zoneChange);
        change.href = filtersHash('#/', filters);
        zone.append(
          element('h2', '', t.dash.zone),
          element('p', 'muted', t.dashboardScope),
          change,
        );
        const side = element('div', 'dash-side');
        side.append(zone, exportBox);
        const pair = element('div', 'dash-pair');
        pair.append(
          stats.por_categoria
            ? recentActivity({ api, filters, signal: controller.signal })
            : lastWeekSection(stats.weekly),
          side,
        );
        const topCounts = stats.top_categorias
          ? Object.fromEntries(
              stats.top_categorias.map((row) => [row.category, row.total]),
            )
          : stats.by_category;
        const top = Object.entries(topCounts)
          .filter(([, count]) => count > 0)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 5)
          .map(([id]) => CATEGORIES.find((category) => category.id === id))
          .filter(Boolean);
        const topSection = top.length
          ? bars(t.dash.topCategories, top, topCounts, stats.total, 'category')
          : element('section', 'bar-section');
        if (!top.length)
          topSection.append(
            element('h2', '', t.dash.topCategories),
            element('p', 'muted', t.dash.noCategories),
          );
        topSection.classList.add('dash-block', 'top-categories');
        const ages = element('section', 'age-buckets dash-block');
        ages.append(element('h2', '', t.dash.ages));
        const ageList = element('ul', 'age-list');
        for (const bucket of ['0-2', '3-7', '8-30', '>30'])
          ageList.append(
            element(
              'li',
              '',
              `${bucket} ${t.dash.days}: ${stats.antiguedad_abiertos[bucket] ?? 0}`,
            ),
          );
        ages.append(ageList);
        const indicators = element('section', 'dash-block');
        indicators.append(
          element('h2', '', t.dash.indicators),
          metricCards(stats, false, listLink),
          element('p', 'muted', t.dash.metricsNote),
        );
        const detail = element('div', 'dash-pair');
        detail.append(topSection, ages);
        const groupBars = bars(
          t.byResolution,
          visibleGroups.map((id) => ({ id, label: t.dash.groups[id] })),
          stats.by_state_group,
          stats.total,
          'state_group',
        );
        groupBars.classList.add('dash-block');
        body.append(
          allTimeSection(stats),
          metricCards(stats, true, listLink),
          pair,
          detail,
          ...(stats.por_categoria ? [categoryCharts(stats.por_categoria)] : []),
          indicators,
          groupBars,
          element('p', 'muted', t.dash.filterLimits),
          element('p', 'muted', t.dash.zoneLimits),
        );
        const cross = element('div');
        async function loadCategoryGroups() {
          const categories = filters.category
            ? CATEGORIES.filter(({ id }) => id === filters.category)
            : CATEGORIES;
          try {
            const rows = await Promise.all(
              categories.map(async (category) => ({
                category,
                stats: filters.category
                  ? stats
                  : await api.getStats(
                      { ...filters, category: category.id },
                      { signal: controller.signal },
                    ),
              })),
            );
            if (current !== generation) return;
            cross.replaceChildren(categoryTable(rows, visibleGroups, listLink));
          } catch (error) {
            if (current !== generation || error.name === 'AbortError') return;
            const retry = element('button', 'retry-button', t.retry);
            retry.type = 'button';
            retry.addEventListener('click', load);
            cross.replaceChildren(
              element('p', 'error-message', t.dash.crossError),
              retry,
            );
          }
        }
        if (stats.por_categoria) {
          // Preserve the detailed v0.2 cross-tab without six eager stats calls.
          const details = element(
            'details',
            'category-group-detail dash-block',
          );
          details.append(element('summary', '', t.dash.categoryGroups), cross);
          let loaded = false;
          details.addEventListener('toggle', () => {
            if (current === generation && details.open && !loaded) {
              loaded = true;
              loadCategoryGroups();
            }
          });
          body.append(details);
        } else {
          body.append(cross);
          await loadCategoryGroups();
        }
      }
      title.focus({ preventScroll: true });
    } catch (error) {
      if (current !== generation || error.name === 'AbortError') return;
      const message = element('p', 'error-message', t.dashboardError);
      message.setAttribute('role', 'alert');
      const retry = element('button', 'retry-button', t.retry);
      retry.type = 'button';
      retry.addEventListener('click', load);
      body.replaceChildren(message, retry);
      root.replaceChildren(band, body);
    } finally {
      if (current === generation) root.setAttribute('aria-busy', 'false');
    }
  }
  load();
  return {
    destroy() {
      generation++;
      controller?.abort();
      revokeCsv();
      root.replaceChildren();
      root.classList.remove('page--dashboard');
      root.removeAttribute('aria-busy');
    },
  };
}
