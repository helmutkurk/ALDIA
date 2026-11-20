import { element } from './dom.js';
import { t } from './i18n.js';
import { number, quantity } from './dashboard-metrics.js';

const SVG = 'http://www.w3.org/2000/svg';
const svgNode = (name, attrs = {}) => {
  const node = document.createElementNS(SVG, name);
  for (const [key, value] of Object.entries(attrs))
    node.setAttribute(key, String(value));
  return node;
};
/** Cumulative running total of one weekly series. @param {Array<object>} weeks @param {string} key */
const cumulative = (weeks, key) => {
  let sum = 0;
  return weeks.map((week) => (sum += week[key]));
};
/** Two-line chart of received and resolved totals plus the two end values.
 * The SVG has an equivalent weekly table; API strings stay text nodes.
 * @param {object} stats
 */
export function allTimeSection(stats) {
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
  const [left, right, top, bottom] = [44, 440, 16, 204];
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
  let previousLabelY;
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
    let labelY = Math.max(28, y(end));
    if (previousLabelY !== undefined && Math.abs(labelY - previousLabelY) < 22)
      labelY = previousLabelY + 22;
    previousLabelY = labelY;
    const directLabel = svgNode('text', {
      x: x(weeks.length - 1) + 12,
      y: labelY,
      class: 'chart-tick',
    });
    directLabel.textContent = `${t.dash[key]}: ${quantity(end)}`;
    svg.append(directLabel);
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
export function lastWeekSection(weeks, options = {}) {
  const section = element('section', 'last-week dash-block');
  section.append(element('h2', '', options.title ?? t.dash.lastWeek));
  if (!weeks.length && options.totals)
    weeks = [{ week: '', recibidos: 0, resueltos: 0 }];
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
    spark.append(
      key === 'recibidos'
        ? svgNode('circle', { cx, cy, r: 4, class: 'spark-dot' })
        : svgNode('rect', {
            x: cx - 3.5,
            y: cy - 3.5,
            width: 7,
            height: 7,
            class: 'spark-dot',
          }),
    );
    const item = element('li', `spark-item spark-item--${key}`);
    item.append(
      spark,
      element(
        'strong',
        'spark-value',
        quantity(options.totals?.[key] ?? values.at(-1)),
      ),
      element('span', 'spark-label', label),
    );
    list.append(item);
  }
  section.append(
    list,
    element(
      'p',
      'muted chart-note',
      options.note ?? t.dash.lastWeekNote(recent.at(-1).week),
    ),
  );
  return section;
}
