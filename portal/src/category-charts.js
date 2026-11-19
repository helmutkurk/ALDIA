/** Accessible v0.3 category charts. All numeric values come from GET /api/stats. */
import { CATEGORIES } from './categories.js';
import { t } from './i18n.js';
import { element } from './panel.js';

const SVG = 'http://www.w3.org/2000/svg';
const number = new Intl.NumberFormat('es-GT', { maximumFractionDigits: 1 });
const hours = (value) =>
  value === null
    ? t.dash.unavailable
    : `${number.format(value)} ${t.dash.hours}`;
const labelFor = (id) =>
  CATEGORIES.find((category) => category.id === id)?.label ?? id;
let tooltipId = 0;

function svgNode(tag, attributes) {
  const node = document.createElementNS(SVG, tag);
  for (const [key, value] of Object.entries(attributes))
    node.setAttribute(key, String(value));
  return node;
}

function dataTable(title, headings, rows) {
  const disclosure = element('details', 'chart-data');
  const summary = element('summary', '', t.dash.seeTable);
  summary.setAttribute('aria-label', t.dash.seeTableFor(title));
  const scroll = element('div', 'chart-table-scroll');
  scroll.tabIndex = 0;
  scroll.setAttribute('role', 'region');
  scroll.setAttribute('aria-label', title);
  const table = element('table');
  table.append(element('caption', 'sr-only', title));
  const head = element('thead');
  const header = element('tr');
  for (const heading of headings) {
    const cell = element('th', '', heading);
    cell.scope = 'col';
    header.append(cell);
  }
  head.append(header);
  const body = element('tbody');
  for (const values of rows) {
    const row = element('tr');
    values.forEach((value, i) => {
      const cell = element(i === 0 ? 'th' : 'td', '', String(value));
      if (i === 0) cell.scope = 'row';
      row.append(cell);
    });
    body.append(row);
  }
  table.append(head, body);
  scroll.append(table);
  disclosure.append(summary, scroll);
  return disclosure;
}

/** One tab stop per category; the whole row keeps the tooltip hoverable. */
function chartRow(label, description, segments) {
  const row = element('li', 'category-chart-row');
  row.append(
    element('strong', '', label),
    element('p', 'category-chart-values', description),
  );
  const svg = svgNode('svg', {
    viewBox: '0 0 640 32',
    class: 'category-chart-svg',
  });
  const target = svgNode('g', {
    tabindex: 0,
    role: 'img',
    'aria-label': description,
  });
  target.append(
    svgNode('rect', { width: 640, height: 32, class: 'category-chart-track' }),
  );
  let x = 0;
  for (const [width, kind] of segments) {
    target.append(
      svgNode('rect', {
        x,
        width,
        height: 32,
        class: `category-chart-bar category-chart-bar--${kind}`,
      }),
    );
    x += width;
  }
  const tooltip = element('div', 'category-chart-tip', description);
  tooltip.id = `category-chart-tip-${++tooltipId}`;
  tooltip.setAttribute('role', 'tooltip');
  tooltip.hidden = true;
  target.setAttribute('aria-describedby', tooltip.id);
  const show = () => {
    tooltip.hidden = false;
  };
  const hide = () => {
    tooltip.hidden = true;
  };
  row.addEventListener('pointerenter', show);
  row.addEventListener('pointerleave', () => {
    if (!row.contains(document.activeElement)) hide();
  });
  target.addEventListener('focusin', show);
  target.addEventListener('focusout', hide);
  target.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') hide();
  });
  svg.append(target);
  row.append(svg, tooltip);
  return row;
}

function chartSection(title, note, className) {
  const section = element('section', `dash-block ${className}`);
  section.append(element('h2', '', title), element('p', 'muted', note));
  return section;
}

export function categoryCharts(rows) {
  const wrap = element('div', 'category-charts');
  const repair = chartSection(
    t.dash.categoryRepair,
    t.dash.categoryRepairNote,
    'category-repair',
  );
  const frequency = chartSection(
    t.dash.categoryFrequency,
    t.dash.categoryFrequencyNote,
    'category-frequency',
  );
  // Zero-count rows stay in the API schema but add no information to the charts.
  const active = rows.filter((row) => row.total > 0);
  if (!active.length) {
    for (const section of [repair, frequency])
      section.append(element('p', 'muted', t.dash.noCategories));
  } else {
    const repairs = element('ul', 'category-chart-list');
    const maxHours = Math.max(
      1,
      ...active.map((row) => row.mediana_reparacion_horas ?? 0),
    );
    for (const row of active) {
      const description = t.dash.repairDescription(
        labelFor(row.category),
        hours(row.mediana_reparacion_horas),
        hours(row.p90_reparacion_horas),
        row.n_resueltos,
      );
      repairs.append(
        chartRow(labelFor(row.category), description, [
          [(640 * (row.mediana_reparacion_horas ?? 0)) / maxHours, 'repair'],
        ]),
      );
    }
    repair.append(
      repairs,
      dataTable(
        t.dash.categoryRepair,
        [t.category, t.dash.median, t.dash.p90, t.dash.repairSamples],
        active.map((row) => [
          labelFor(row.category),
          hours(row.mediana_reparacion_horas),
          hours(row.p90_reparacion_horas),
          row.n_resueltos,
        ]),
      ),
    );
    const ordered = [...active].sort(
      (a, b) => b.total - a.total || a.category.localeCompare(b.category),
    );
    const counts = element('ul', 'category-chart-list');
    const maxCount = Math.max(...ordered.map((row) => row.total));
    const legend = element('ul', 'category-chart-legend');
    for (const key of ['resueltos', 'abiertos', 'cerrados']) {
      const entry = element(
        'li',
        `category-legend--${key}`,
        t.dash.categoryBuckets[key],
      );
      legend.append(entry);
    }
    for (const row of ordered) {
      const description = t.dash.frequencyDescription(
        labelFor(row.category),
        row,
      );
      counts.append(
        chartRow(
          labelFor(row.category),
          description,
          ['resueltos', 'abiertos', 'cerrados'].map((key) => [
            (640 * row[key]) / maxCount,
            key,
          ]),
        ),
      );
    }
    frequency.append(
      legend,
      counts,
      dataTable(
        t.dash.categoryFrequency,
        [
          t.category,
          t.dash.total,
          ...['resueltos', 'abiertos', 'cerrados'].map(
            (key) => t.dash.categoryBuckets[key],
          ),
        ],
        ordered.map((row) => [
          labelFor(row.category),
          row.total,
          row.resueltos,
          row.abiertos,
          row.cerrados,
        ]),
      ),
    );
  }
  wrap.append(repair, frequency);
  return wrap;
}
