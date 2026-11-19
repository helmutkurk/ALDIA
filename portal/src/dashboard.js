import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES, t, staffError } from './i18n.js';
import { element } from './panel.js';
import { filtersHash } from './filters.js';
import { GROUP_COLORS } from './states.js';
import { categoryCharts } from './category-charts.js';

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
  root.classList.add('page--dashboard');
  const back = element('a', 'back-link', t.backToMap);
  back.href = filtersHash('#/', filters);
  const title = element('h1', '', t.dashboard);
  title.tabIndex = -1;
  const scope = element('p', 'dash-scope', t.dashboardScope);
  const band = element('div', 'dash-band');
  band.append(back, title, scope);
  const body = element('div', 'dash-body');
  const SVG = 'http://www.w3.org/2000/svg';
  /** @param {string} name @param {object} attrs */
  const svgNode = (name, attrs = {}) => {
    const node = document.createElementNS(SVG, name);
    for (const [key, value] of Object.entries(attrs))
      node.setAttribute(key, String(value));
    return node;
  };
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
  function metricCards(stats, headline = false) {
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
    if (headline) cards.classList.add('kpi-strip');
    cards.setAttribute(
      'aria-label',
      headline ? t.dash.kpiStrip : t.dash.indicators,
    );
    for (const key of headline
      ? [
          'recibidos',
          'rechazados_verificador',
          'abiertos',
          'resueltos',
          'cerrados_sin_solucion',
        ]
      : []) {
      card(
        key,
        quantity(stats[key]),
        undefined,
        key === 'rechazados_verificador'
          ? { state: 'rechazado_verificador', state_group: '' }
          : undefined,
      );
    }
    if (headline) return cards;
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
  /** Cumulative running total of one weekly series. @param {Array<object>} weeks @param {string} key */
  const cumulative = (weeks, key) => {
    let sum = 0;
    return weeks.map((week) => (sum += week[key]));
  };
  /** Two-line chart of received and resolved totals plus the two end values.
   * The SVG has an equivalent weekly table; API strings stay text nodes.
   * @param {object} stats
   */
  function allTimeSection(stats) {
    const weeks = stats.weekly;
    const section = element('section', 'weekly-chart dash-block');
    section.append(element('h2', '', t.dash.allTime));
    if (!weeks.length) {
      section.append(element('p', 'muted', t.dash.noWeeks));
      return section;
    }
    const series = {
      recibidos: cumulative(weeks, 'recibidos'),
      resueltos: cumulative(weeks, 'resueltos'),
    };
    const max = Math.max(1, ...series.recibidos, ...series.resueltos);
    const [left, right, top, bottom] = [44, 620, 16, 204];
    const x = (i) =>
      weeks.length === 1
        ? (left + right) / 2
        : left + (i * (right - left)) / (weeks.length - 1);
    const y = (value) => bottom - ((bottom - top) * value) / max;
    const svg = svgNode('svg', {
      viewBox: '0 0 640 236',
      role: 'img',
      class: 'all-time-chart',
    });
    svg.setAttribute('aria-label', t.dash.allTime);
    for (const fraction of [0, 0.5, 1]) {
      const value = max * fraction;
      svg.append(
        svgNode('line', {
          x1: left,
          x2: right,
          y1: y(value),
          y2: y(value),
          class: 'chart-grid',
        }),
      );
      const label = svgNode('text', {
        x: left - 8,
        y: y(value) + 4,
        'text-anchor': 'end',
        class: 'chart-tick',
      });
      label.textContent = number.format(Math.round(value));
      svg.append(label);
    }
    for (const index of new Set([
      0,
      Math.floor((weeks.length - 1) / 2),
      weeks.length - 1,
    ])) {
      const label = svgNode('text', {
        x: x(index),
        y: 226,
        'text-anchor':
          index === 0 && weeks.length > 1
            ? 'start'
            : index === weeks.length - 1 && weeks.length > 1
              ? 'end'
              : 'middle',
        class: 'chart-tick',
      });
      label.textContent = weeks[index].week;
      svg.append(label);
    }
    for (const key of ['recibidos', 'resueltos']) {
      const line = svgNode('polyline', {
        points: series[key].map((value, i) => `${x(i)},${y(value)}`).join(' '),
        class: `weekly-line weekly-line--${key}`,
        fill: 'none',
      });
      const lineTitle = document.createElementNS(SVG, 'title');
      lineTitle.textContent = t.dash[key];
      line.append(lineTitle);
      svg.append(line);
      const end = series[key].at(-1);
      // Different end markers keep the two series apart without relying on colour.
      svg.append(
        key === 'recibidos'
          ? svgNode('circle', {
              cx: x(weeks.length - 1),
              cy: y(end),
              r: 5,
              class: 'weekly-dot weekly-dot--recibidos',
            })
          : svgNode('rect', {
              x: x(weeks.length - 1) - 4.5,
              y: y(end) - 4.5,
              width: 9,
              height: 9,
              class: 'weekly-dot weekly-dot--resueltos',
            }),
      );
    }
    const figure = element('div', 'chart-figure');
    figure.append(svg);
    const totals = element('dl', 'chart-totals');
    for (const [key, label] of [
      ['recibidos', t.dash.receivedLabel],
      ['resueltos', t.dash.resolvedLabel],
    ]) {
      const group = element('div', `chart-total chart-total--${key}`);
      group.append(
        element('dd', '', quantity(stats[key])),
        element('dt', '', label),
      );
      totals.append(group);
    }
    const wrap = element('div', 'chart-layout');
    wrap.append(figure, totals);
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
    const tbody = element('tbody');
    for (const week of weeks) {
      const bodyRow = element('tr');
      const heading = element('th', '', week.week);
      heading.scope = 'row';
      bodyRow.append(
        heading,
        element('td', '', String(week.recibidos)),
        element('td', '', String(week.resueltos)),
      );
      tbody.append(bodyRow);
    }
    table.append(head, tbody);
    const data = element('details', 'chart-data');
    data.append(element('summary', '', t.dash.weekly), table);
    section.append(
      element('p', 'chart-legend', t.dash.weeklyLegend),
      wrap,
      element('p', 'muted chart-note', t.dash.allTimeNote),
      data,
    );
    return section;
  }
  /** Last weeks of the API weekly series: the API has no daily series, so no 7-day claim is made.
   * Only fields the contract provides are shown; there is no source for "updates".
   * @param {Array<{week: string, recibidos: number, resueltos: number}>} weeks
   */
  function lastWeekSection(weeks) {
    const section = element('section', 'last-week dash-block');
    section.append(element('h2', '', t.dash.lastWeek));
    if (!weeks.length) {
      section.append(element('p', 'muted', t.dash.noWeeks));
      return section;
    }
    const recent = weeks.slice(-8);
    const list = element('ul', 'sparklines');
    for (const [key, label] of [
      ['recibidos', t.dash.recibidos],
      ['resueltos', t.dash.resueltos],
    ]) {
      const values = recent.map((week) => week[key]);
      const max = Math.max(1, ...values);
      const point = (value, i) => [
        recent.length === 1 ? 60 : 6 + (i * 108) / (recent.length - 1),
        34 - (28 * value) / max,
      ];
      const spark = svgNode('svg', {
        viewBox: '0 0 120 40',
        class: `spark spark--${key}`,
        role: 'img',
      });
      spark.setAttribute(
        'aria-label',
        t.dash.sparkLabel(label, values.join(', ')),
      );
      if (recent.length > 1)
        spark.append(
          svgNode('path', {
            d: values
              .map((value, i) => `${i ? 'L' : 'M'}${point(value, i).join(' ')}`)
              .join(' '),
            fill: 'none',
            class: 'spark-line',
          }),
        );
      const [cx, cy] = point(values.at(-1), values.length - 1);
      spark.append(svgNode('circle', { cx, cy, r: 4, class: 'spark-dot' }));
      const item = element('li', `spark-item spark-item--${key}`);
      item.append(
        spark,
        element('strong', 'spark-value', quantity(values.at(-1))),
        element('span', 'spark-label', label),
      );
      list.append(item);
    }
    section.append(
      list,
      element('p', 'muted chart-note', t.dash.lastWeekNote(recent.at(-1).week)),
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
        pair.append(lastWeekSection(stats.weekly), side);
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
          metricCards(stats),
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
          metricCards(stats, true),
          ...(stats.por_categoria ? [categoryCharts(stats.por_categoria)] : []),
          allTimeSection(stats),
          pair,
          detail,
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
