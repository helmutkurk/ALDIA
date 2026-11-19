import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES, t, staffError } from './i18n.js';
import { element } from './panel.js';
import { filtersHash } from './filters.js';
import { GROUP_COLORS } from './states.js';

const groups = Object.keys(t.dash.groups);
const number = new Intl.NumberFormat('es-GT', { maximumFractionDigits: 1 });
/** Null metrics are deliberately not rendered as zero. @param {number|null} value */
const quantity = (value) =>
  value === null || value === undefined
    ? t.dash.unavailable
    : number.format(value);
/** @param {number|null} value */
const percent = (value) =>
  value === null || value === undefined
    ? t.dash.unavailable
    : `${number.format(value * 100)} %`;

/** Filtered municipal statistics. Calculations stay on the API, never on a list page.
 * @param {HTMLElement} root
 * @param {{api: ReturnType<import('./api.js').createApiClient>, filters: import('./api.js').ReportQuery}} options
 */
export function createDashboard(root, { api, filters }) {
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
  const back = element('a', 'back-link', t.backToMap);
  back.href = filtersHash('#/', filters);
  const title = element('h1', '', t.dashboard);
  title.tabIndex = -1;
  const scope = element('p', 'muted', t.dashboardScope);
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
    return section;
  }
  /** @param {object} stats */
  function metricCards(stats) {
    const cards = element('dl', 'metric-cards');
    /** @param {string} key @param {string} value @param {number} [n] @param {object} [patch] */
    function card(key, value, n, patch) {
      const wrapper = element('div', 'metric-card');
      const label = element('dt', '', t.dash[key]);
      const data = element('dd');
      data.append(patch ? listLink(value, patch) : element('span', '', value));
      if (n !== null && n !== undefined)
        data.append(element('small', '', t.dash.sample(n)));
      wrapper.append(label, data);
      cards.append(wrapper);
    }
    for (const key of [
      'recibidos',
      'rechazados_verificador',
      'abiertos',
      'resueltos',
      'cerrados_sin_solucion',
    ]) {
      card(
        key,
        quantity(stats[key]),
        undefined,
        key === 'rechazados_verificador'
          ? { state: 'rechazado_verificador', state_group: '' }
          : undefined,
      );
    }
    const denominator =
      stats.recibidos -
      (stats.by_state.duplicado ?? 0) -
      (stats.by_state.fuera_de_competencia ?? 0);
    card(
      'tasa_resolucion',
      percent(stats.tasa_resolucion),
      Math.max(0, denominator),
    );
    for (const key of ['median', 'p90', 'mean']) {
      card(
        key,
        stats.resolucion_horas[key] === null
          ? t.dash.unavailable
          : `${quantity(stats.resolucion_horas[key])} ${t.dash.hours}`,
        stats.resolucion_horas.n,
      );
    }
    for (const [key, field] of [
      ['first', 'median'],
      ['firstP90', 'p90'],
    ]) {
      card(
        key,
        stats.primera_respuesta_horas[field] === null
          ? t.dash.unavailable
          : `${quantity(stats.primera_respuesta_horas[field])} ${t.dash.hours}`,
        stats.primera_respuesta_horas.n,
      );
    }
    card('sla_cumplido', percent(stats.sla_cumplido), stats.resolucion_horas.n);
    card('vencidos', quantity(stats.vencidos));
    return cards;
  }
  /** Accessible SVG has an equivalent data table. Dynamic strings remain text nodes.
   * @param {Array<{week: string, recibidos: number, resueltos: number}>} weeks
   */
  function weeklyChart(weeks) {
    const section = element('section', 'weekly-chart');
    section.append(element('h2', '', t.dash.weekly));
    if (!weeks.length) {
      section.append(element('p', 'muted', t.dash.noWeeks));
      return section;
    }
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 640 240');
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', t.dash.weekly);
    const max = Math.max(
      1,
      ...weeks.flatMap((week) => [week.recibidos, week.resueltos]),
    );
    for (const key of ['recibidos', 'resueltos']) {
      const line = document.createElementNS(
        'http://www.w3.org/2000/svg',
        'polyline',
      );
      line.setAttribute(
        'points',
        weeks
          .map(
            (week, i) =>
              `${weeks.length === 1 ? 320 : 20 + (i * 600) / (weeks.length - 1)},${220 - (200 * week[key]) / max}`,
          )
          .join(' '),
      );
      line.setAttribute('class', `weekly-line weekly-line--${key}`);
      line.setAttribute('fill', 'none');
      line.setAttribute(
        'stroke',
        key === 'recibidos' ? 'var(--primary)' : 'var(--success)',
      );
      line.setAttribute('stroke-width', '3');
      if (key === 'resueltos') line.setAttribute('stroke-dasharray', '8 4');
      const lineTitle = document.createElementNS(
        'http://www.w3.org/2000/svg',
        'title',
      );
      lineTitle.textContent = t.dash[key];
      line.append(lineTitle);
      svg.append(line);
      weeks.forEach((week, index) => {
        const point = document.createElementNS(
          'http://www.w3.org/2000/svg',
          'circle',
        );
        point.setAttribute(
          'cx',
          String(
            weeks.length === 1 ? 320 : 20 + (index * 600) / (weeks.length - 1),
          ),
        );
        point.setAttribute('cy', String(220 - (200 * week[key]) / max));
        point.setAttribute('r', key === 'recibidos' ? '4' : '3');
        point.setAttribute(
          'fill',
          key === 'recibidos' ? 'var(--primary)' : 'var(--success)',
        );
        svg.append(point);
      });
    }
    const table = element('table', 'weekly-table');
    table.append(element('caption', '', t.dash.weekly));
    const head = element('thead');
    const row = element('tr');
    for (const label of [t.dash.week, t.dash.recibidos, t.dash.resueltos]) {
      const cell = element('th', '', label);
      cell.scope = 'col';
      row.append(cell);
    }
    head.append(row);
    const body = element('tbody');
    for (const week of weeks) {
      const row = element('tr');
      const heading = element('th', '', week.week);
      heading.scope = 'row';
      row.append(
        heading,
        element('td', '', String(week.recibidos)),
        element('td', '', String(week.resueltos)),
      );
      body.append(row);
    }
    table.append(head, body);
    section.append(
      element('p', 'chart-legend', t.dash.weeklyLegend),
      svg,
      table,
    );
    return section;
  }
  /** Each category query supplies the actual joint distribution, not an estimate.
   * @param {{category: {id: string, label: string}, stats: object}[]} rows
   */
  function categoryTable(rows) {
    const section = element('section', 'category-groups');
    section.append(element('h2', '', t.dash.categoryGroups));
    const table = element('table');
    table.append(element('caption', 'sr-only', t.dash.categoryGroups));
    const head = element('thead');
    const headings = element('tr');
    for (const label of [
      t.category,
      ...visibleGroups.map((id) => t.dash.groups[id]),
      t.dash.median,
      t.dash.distribution,
    ]) {
      const cell = element('th', '', label);
      cell.scope = 'col';
      headings.append(cell);
    }
    head.append(headings);
    const body = element('tbody');
    const totals = Object.fromEntries(visibleGroups.map((group) => [group, 0]));
    for (const { category, stats } of rows) {
      const row = element('tr');
      const name = element('th', '', category.label);
      name.scope = 'row';
      row.append(name);
      for (const group of visibleGroups) {
        const count = stats.by_state_group[group] ?? 0;
        totals[group] += count;
        const cell = element('td');
        cell.append(
          listLink(String(count), {
            category: category.id,
            state_group: group,
          }),
        );
        row.append(cell);
      }
      row.append(
        element(
          'td',
          '',
          stats.resolucion_horas.median === null
            ? t.dash.unavailable
            : `${quantity(stats.resolucion_horas.median)} ${t.dash.hours}`,
        ),
      );
      const distribution = element('td');
      const stack = document.createElementNS(
        'http://www.w3.org/2000/svg',
        'svg',
      );
      stack.setAttribute('viewBox', '0 0 240 24');
      stack.setAttribute('width', '240');
      stack.setAttribute('height', '24');
      stack.setAttribute('role', 'img');
      stack.setAttribute(
        'aria-label',
        `${category.label}: ${visibleGroups.map((group) => `${t.dash.groups[group]} ${stats.by_state_group[group] ?? 0}`).join(', ')}`,
      );
      const total = Math.max(
        1,
        visibleGroups.reduce(
          (sum, group) => sum + (stats.by_state_group[group] ?? 0),
          0,
        ),
      );
      let x = 0;
      for (const group of visibleGroups) {
        const rect = document.createElementNS(
          'http://www.w3.org/2000/svg',
          'rect',
        );
        const width = (240 * (stats.by_state_group[group] ?? 0)) / total;
        rect.setAttribute('x', String(x));
        rect.setAttribute('width', String(width));
        rect.setAttribute('height', '24');
        rect.setAttribute('fill', GROUP_COLORS[group]);
        stack.append(rect);
        x += width;
      }
      distribution.append(stack);
      row.append(distribution);
      body.append(row);
    }
    const footer = element('tfoot');
    const totalRow = element('tr');
    const totalLabel = element('th', '', t.dash.total);
    totalLabel.scope = 'row';
    totalRow.append(totalLabel);
    for (const group of visibleGroups)
      totalRow.append(element('td', '', String(totals[group])));
    totalRow.append(element('td', '', t.dash.unavailable));
    totalRow.append(element('td'));
    footer.append(totalRow);
    table.append(head, body, footer);
    const medians = element('section', 'bar-section');
    medians.append(element('h2', '', t.dash.categoryMedian));
    const maxMedian = Math.max(
      1,
      ...rows.map((row) => row.stats.resolucion_horas.median ?? 0),
    );
    const medianList = element('ul', 'bar-list');
    for (const { category, stats } of rows) {
      const row = element('li');
      const value = stats.resolucion_horas.median;
      row.append(
        element(
          'span',
          '',
          `${category.label}: ${value === null ? t.dash.unavailable : quantity(value) + ' ' + t.dash.hours}`,
        ),
      );
      const meter = element('meter');
      meter.min = 0;
      meter.max = maxMedian;
      meter.value = value ?? 0;
      meter.setAttribute(
        'aria-label',
        `${category.label}: ${quantity(value)} ${t.dash.hours}`,
      );
      row.append(meter);
      medianList.append(row);
    }
    medians.append(medianList);
    section.append(table, medians);
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
      root.replaceChildren(
        back,
        title,
        scope,
        element('p', 'dashboard-total', t.totalReports(stats.total)),
        delimiterLabel,
        csv,
        csvStatus,
      );
      if (stats.recibidos === undefined) {
        root.append(
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
        root.append(
          metricCards(stats),
          element('p', 'muted', t.dash.metricsNote),
        );
        const ages = element('section', 'age-buckets');
        ages.append(element('h2', '', t.dash.ages));
        for (const bucket of ['0-2', '3-7', '8-30', '>30'])
          ages.append(
            element(
              'p',
              '',
              `${bucket} ${t.dash.days}: ${stats.antiguedad_abiertos[bucket]}`,
            ),
          );
        root.append(
          ages,
          bars(
            t.byResolution,
            visibleGroups.map((id) => ({ id, label: t.dash.groups[id] })),
            stats.by_state_group,
            stats.total,
            'state_group',
          ),
          weeklyChart(stats.weekly),
          element('p', 'muted', t.dash.filterLimits),
          element('p', 'muted', t.dash.zoneLimits),
        );
        const categories = filters.category
          ? CATEGORIES.filter(({ id }) => id === filters.category)
          : CATEGORIES;
        const cross = element('div');
        root.append(cross);
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
          cross.replaceChildren(categoryTable(rows));
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
      revokeCsv();
      root.replaceChildren();
      root.removeAttribute('aria-busy');
    },
  };
}
