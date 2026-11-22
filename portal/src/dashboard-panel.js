import { categoryLabel } from './categories.js';
import { element } from './dom.js';
import { t, ui } from './i18n.js';

const SVG_NS = 'http://www.w3.org/2000/svg';
const one = new Intl.NumberFormat('es-GT', {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});
const whole = new Intl.NumberFormat('es-GT', { maximumFractionDigits: 0 });
const s = ui.stats;

const finite = (value) => typeof value === 'number' && Number.isFinite(value);
const count = (value) =>
  Number.isSafeInteger(value) ? whole.format(value) : t.dash.unavailable;
const hours = (value) =>
  finite(value) ? `${whole.format(value)} h` : t.dash.unavailable;
const days = (value) =>
  finite(value) ? `${one.format(value / 24)} d` : t.dash.unavailable;
const percent = (value) =>
  finite(value) ? `${one.format(value * 100)} %` : t.dash.unavailable;

/** Signed change against the previous period, or null when either side is missing.
 * @param {'count'|'rate'|'days'|'hours'} kind */
function change(now, before, kind) {
  if (!finite(now) || !finite(before)) return null;
  const diff = now - before;
  const sign = diff > 0 ? '+' : diff < 0 ? '−' : '±';
  const size = Math.abs(diff);
  if (kind === 'count')
    return before > 0
      ? { diff, text: `${sign}${whole.format((size / before) * 100)} %` }
      : null;
  if (kind === 'rate')
    return { diff, text: `${sign}${one.format(size * 100)} pts` };
  if (kind === 'days')
    return { diff, text: `${sign}${one.format(size / 24)} d` };
  return { diff, text: `${sign}${whole.format(size)} h` };
}

/** One KPI card: label, value, change vs. the previous period and the sample size. */
function kpi(label, value, delta, better, n) {
  const card = element('article', 'stat-kpi');
  card.append(
    element('span', 'stat-kpi-label', label),
    element('span', 'stat-kpi-value', value),
  );
  const foot = element('span', 'stat-kpi-foot');
  if (delta) {
    const tone =
      delta.diff === 0 || !better
        ? 'flat'
        : delta.diff > 0 === (better === 'up')
          ? 'good'
          : 'bad';
    foot.append(
      element('span', `stat-delta stat-delta--${tone}`, delta.text),
      document.createTextNode(` ${s.vsPrevious}`),
    );
  } else foot.append(document.createTextNode(s.noComparison));
  if (Number.isSafeInteger(n))
    foot.append(element('span', 'stat-kpi-n', ` · ${t.dash.sample(n)}`));
  card.append(foot);
  return card;
}

/** @param {object} stats @param {object|null} previous @param {boolean} compare */
export function kpiCards(stats, previous, compare) {
  const section = element('section', 'stat-kpis');
  section.setAttribute('aria-label', t.dash.kpiStrip);
  const p = compare ? previous : null;
  const denominator =
    stats.recibidos -
    (stats.by_state?.duplicado ?? 0) -
    (stats.by_state?.fuera_de_competencia ?? 0);
  section.append(
    kpi(
      t.dash.recibidos,
      count(stats.recibidos),
      p && change(stats.recibidos, p.recibidos, 'count'),
      null,
    ),
    kpi(
      t.dash.tasa_resolucion,
      percent(stats.tasa_resolucion),
      p && change(stats.tasa_resolucion, p.tasa_resolucion, 'rate'),
      'up',
      Number.isSafeInteger(stats.tasa_resolucion_n)
        ? stats.tasa_resolucion_n
        : Math.max(0, denominator),
    ),
    kpi(
      s.medianRepair,
      days(stats.resolucion_horas?.median),
      p &&
        change(
          stats.resolucion_horas?.median,
          p.resolucion_horas?.median,
          'days',
        ),
      'down',
      stats.resolucion_horas?.n,
    ),
    kpi(
      s.firstResponse,
      hours(stats.primera_respuesta_horas?.median),
      p &&
        change(
          stats.primera_respuesta_horas?.median,
          p.primera_respuesta_horas?.median,
          'hours',
        ),
      'down',
      stats.primera_respuesta_horas?.n,
    ),
  );
  return section;
}

const svgNode = (tag, attrs = {}) => {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [name, value] of Object.entries(attrs))
    node.setAttribute(name, String(value));
  return node;
};
/** "2026-W47" becomes "S47"; anything else is shown as plain text, never parsed as markup. */
const weekLabel = (week) => {
  const match = /^\d{4}-W(\d{2})$/.exec(String(week));
  return match ? `S${match[1]}` : String(week).slice(0, 12);
};

/** Weekly received vs. resolved lines with totals on the right and a table for screen readers. */
export function trendCard(stats) {
  const card = element('article', 'stat-card stat-trend');
  const main = element('div', 'stat-trend-main');
  const head = element('div', 'stat-card-head');
  const titles = element('div');
  titles.append(
    element('h2', '', t.dash.weekly),
    element('p', 'stat-card-sub', s.trendSub),
  );
  const legend = element('div', 'stat-legend');
  for (const [name, cls] of [
    [t.dash.recibidos, 'received'],
    [t.dash.resueltos, 'resolved'],
  ]) {
    const item = element('span');
    const swatch = element('span', `stat-swatch stat-swatch--${cls}`);
    swatch.setAttribute('aria-hidden', 'true');
    item.append(swatch, document.createTextNode(name));
    legend.append(item);
  }
  head.append(titles, legend);
  main.append(head);
  const weeks = (Array.isArray(stats.weekly) ? stats.weekly : []).map((w) => ({
    week: w.week,
    recibidos: Number.isSafeInteger(w.recibidos) ? w.recibidos : 0,
    resueltos: Number.isSafeInteger(w.resueltos) ? w.resueltos : 0,
  }));
  if (weeks.length < 2) main.append(element('p', 'muted', t.dash.noWeeks));
  else {
    const W = 900;
    const H = 220;
    const left = 40;
    const right = 880;
    const top = 12;
    const bottom = 190;
    const max = Math.max(
      1,
      ...weeks.map((w) => Math.max(w.recibidos, w.resueltos)),
    );
    const step = Math.max(1, Math.ceil(max / 4));
    const ceiling = step * 4;
    const x = (i) => left + (i * (right - left)) / (weeks.length - 1);
    const y = (v) => bottom - (v / ceiling) * (bottom - top);
    const svg = svgNode('svg', {
      viewBox: `0 0 ${W} ${H}`,
      class: 'stat-trend-chart',
      'aria-hidden': 'true',
    });
    for (let i = 0; i <= 4; i++) {
      const value = step * i;
      svg.append(
        svgNode('line', {
          x1: left,
          x2: right,
          y1: y(value),
          y2: y(value),
          class: 'stat-grid',
        }),
      );
      const label = svgNode('text', {
        x: left - 10,
        y: y(value) + 4,
        'text-anchor': 'end',
        class: 'stat-axis',
      });
      label.textContent = String(value);
      svg.append(label);
    }
    const points = (key) =>
      weeks
        .map((w, i) => `${x(i).toFixed(1)},${y(w[key]).toFixed(1)}`)
        .join(' ');
    svg.append(
      svgNode('path', {
        d: `M${x(0)},${bottom} L${points('recibidos').replaceAll(' ', ' L')} L${x(weeks.length - 1)},${bottom} Z`,
        class: 'stat-area',
      }),
      svgNode('polyline', {
        points: points('recibidos'),
        class: 'stat-line stat-line--received',
      }),
      svgNode('polyline', {
        points: points('resueltos'),
        class: 'stat-line stat-line--resolved',
      }),
    );
    const every = Math.ceil(weeks.length / 10);
    weeks.forEach((w, i) => {
      if (i % every && i !== weeks.length - 1) return;
      const label = svgNode('text', {
        x: x(i),
        y: 214,
        'text-anchor': 'middle',
        class: 'stat-axis',
      });
      label.textContent = weekLabel(w.week);
      svg.append(label);
    });
    main.append(svg);
  }
  // Text alternative with the exact weekly numbers.
  const table = element('table', 'weekly-table');
  table.append(element('caption', '', t.dash.weekly));
  const headRow = element('tr');
  for (const label of [t.dash.week, t.dash.recibidos, t.dash.resueltos]) {
    const th = element('th', '', label);
    th.scope = 'col';
    headRow.append(th);
  }
  const thead = element('thead');
  thead.append(headRow);
  const tbody = element('tbody');
  for (const w of weeks) {
    const row = element('tr');
    const th = element('th', '', String(w.week));
    th.scope = 'row';
    row.append(
      th,
      element('td', '', String(w.recibidos)),
      element('td', '', String(w.resueltos)),
    );
    tbody.append(row);
  }
  table.append(thead, tbody);
  const hidden = element('div', 'sr-only');
  hidden.append(table);
  main.append(hidden);
  const totals = element('div', 'stat-trend-totals');
  for (const [value, label, cls] of [
    [stats.recibidos, s.receivedInPeriod, 'received'],
    [stats.resueltos, s.resolvedInPeriod, 'resolved'],
    [stats.rechazados_verificador, s.rejectedInPeriod, 'plain'],
  ]) {
    const item = element('div', 'stat-total');
    item.append(
      element(
        'span',
        `stat-total-value stat-total-value--${cls}`,
        count(value),
      ),
      element('span', 'stat-total-label', label),
    );
    totals.append(item);
  }
  card.append(main, totals);
  return card;
}

const cardShell = (cls, title, sub) => {
  const card = element('article', `stat-card ${cls}`);
  const head = element('div', 'stat-card-head');
  const titles = element('div');
  titles.append(element('h2', '', title));
  if (sub) titles.append(element('p', 'stat-card-sub', sub));
  head.append(titles);
  card.append(head);
  return { card, head };
};
const bar = (cls, width) => {
  const node = element('span', cls);
  node.style.width = `${Math.max(0, Math.min(100, width)).toFixed(1)}%`;
  return node;
};

/** Median repair time per category (bar) with the p90 marker. */
export function repairCard(rows) {
  const { card } = cardShell('stat-repair', s.repairTitle, s.repairSub);
  const usable = (rows ?? []).filter((row) =>
    Number.isSafeInteger(row.n_resueltos),
  );
  const max = Math.max(
    1,
    ...usable.map((row) =>
      Math.max(
        finite(row.p90_reparacion_horas) ? row.p90_reparacion_horas : 0,
        finite(row.mediana_reparacion_horas) ? row.mediana_reparacion_horas : 0,
      ),
    ),
  );
  if (!usable.some((row) => row.n_resueltos > 0)) {
    card.append(element('p', 'muted', s.noRepairs));
    return card;
  }
  const list = element('ul', 'stat-rows');
  for (const row of usable) {
    const item = element('li', 'stat-row');
    const name = element('span', 'stat-row-label', categoryLabel(row.category));
    name.append(element('span', 'stat-row-n', ` · ${row.n_resueltos}`));
    const track = element('span', 'stat-track');
    track.setAttribute('aria-hidden', 'true');
    if (finite(row.mediana_reparacion_horas))
      track.append(bar('stat-bar', (row.mediana_reparacion_horas / max) * 100));
    if (finite(row.p90_reparacion_horas)) {
      const marker = element('span', 'stat-p90');
      marker.style.left = `${Math.min(100, (row.p90_reparacion_horas / max) * 100).toFixed(1)}%`;
      track.append(marker);
    }
    const value = element(
      'span',
      'stat-row-value',
      days(row.mediana_reparacion_horas),
    );
    value.title = `p90 ${days(row.p90_reparacion_horas)}`;
    item.append(name, track, value);
    list.append(item);
  }
  card.append(list);
  return card;
}

/** Reports per category, stacked by current state. @param {(text: string, patch: object) => HTMLAnchorElement} listLink */
export function frequencyCard(rows, listLink) {
  const { card, head } = cardShell(
    'stat-frequency',
    s.frequencyTitle,
    s.frequencySub,
  );
  const legend = element('div', 'stat-legend');
  for (const key of ['resueltos', 'abiertos', 'cerrados']) {
    const item = element('span');
    const swatch = element('span', `stat-swatch stat-swatch--${key}`);
    swatch.setAttribute('aria-hidden', 'true');
    item.append(swatch, document.createTextNode(t.dash.categoryBuckets[key]));
    legend.append(item);
  }
  head.append(legend);
  const sorted = (rows ?? [])
    .filter((row) => Number.isSafeInteger(row.total) && row.total > 0)
    .sort((a, b) => b.total - a.total)
    .slice(0, 6);
  if (!sorted.length) {
    card.append(element('p', 'muted', t.dash.noCategories));
    return card;
  }
  const max = Math.max(...sorted.map((row) => row.total));
  const list = element('ul', 'stat-rows');
  for (const row of sorted) {
    const item = element('li', 'stat-row');
    const name = listLink(categoryLabel(row.category), {
      category: row.category,
    });
    name.className = 'stat-row-label';
    const stack = element('span', 'stat-stack');
    stack.setAttribute('aria-hidden', 'true');
    for (const key of ['resueltos', 'abiertos', 'cerrados']) {
      const value = Number.isSafeInteger(row[key]) ? row[key] : 0;
      if (value > 0)
        stack.append(bar(`stat-seg stat-seg--${key}`, (value / max) * 100));
    }
    const total = element('span', 'stat-row-value', count(row.total));
    total.title = t.dash.frequencyDescription(categoryLabel(row.category), row);
    item.append(name, stack, total);
    list.append(item);
  }
  card.append(list);
  return card;
}

/** Open reports by days since verification; more than 30 days is highlighted. */
export function agesCard(ages = {}) {
  const { card } = cardShell('stat-ages age-buckets', s.agesTitle, s.agesSub);
  const buckets = ['0-2', '3-7', '8-30', '>30'];
  const values = buckets.map((id) =>
    Number.isSafeInteger(ages[id]) ? ages[id] : 0,
  );
  const max = Math.max(1, ...values);
  const chart = element('ul', 'stat-columns');
  buckets.forEach((id, index) => {
    const item = element('li', 'stat-column');
    const column = element(
      'span',
      `stat-column-bar${id === '>30' ? ' stat-column-bar--late' : ''}`,
    );
    column.style.height = `${Math.max(2, (values[index] / max) * 100).toFixed(1)}%`;
    column.setAttribute('aria-hidden', 'true');
    item.append(
      element('span', 'stat-column-value', String(values[index])),
      column,
      element('span', 'stat-column-label', `${id} ${t.dash.days}`),
    );
    chart.append(item);
  });
  card.append(chart);
  if (values[3] > 0)
    card.append(element('p', 'stat-alert', s.agesLate(values[3])));
  return card;
}

/** Median and p90 for first response and repair, plus the share within the deadline. */
export function timesCard(stats) {
  const { card } = cardShell('stat-times', s.timesTitle, s.timesSub);
  const list = element('ul', 'stat-time-list');
  const row = (label, desc, median, p90, n) => {
    const item = element('li', 'stat-time');
    const name = element('span', 'stat-time-name');
    name.append(
      element('span', 'stat-time-label', label),
      element('span', 'stat-time-desc', desc),
    );
    const first = element('span', 'stat-time-cell');
    first.append(
      element('span', 'stat-time-value', median.value),
      element('span', 'stat-time-unit', median.unit),
    );
    const second = element('span', 'stat-time-cell');
    second.append(
      element('span', 'stat-time-value stat-time-value--muted', p90.value),
      element(
        'span',
        'stat-time-unit',
        n === undefined ? p90.unit : `${p90.unit} · n ${count(n)}`,
      ),
    );
    item.append(name, first, second);
    list.append(item);
  };
  row(
    s.firstResponse,
    s.firstResponseDesc,
    { value: hours(stats.primera_respuesta_horas?.median), unit: s.median },
    { value: hours(stats.primera_respuesta_horas?.p90), unit: 'p90' },
    stats.primera_respuesta_horas?.n,
  );
  row(
    s.repair,
    s.repairDesc,
    { value: hours(stats.resolucion_horas?.median), unit: s.median },
    { value: hours(stats.resolucion_horas?.p90), unit: 'p90' },
    stats.resolucion_horas?.n,
  );
  row(
    s.withinDeadline,
    s.withinDeadlineDesc,
    { value: percent(stats.sla_cumplido), unit: s.share },
    { value: count(stats.vencidos), unit: t.dash.vencidos.toLowerCase() },
  );
  card.append(list);
  return card;
}
