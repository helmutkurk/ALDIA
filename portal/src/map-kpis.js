import { element } from './dom.js';
import { ui } from './i18n.js';

const SVG_NS = 'http://www.w3.org/2000/svg';
const days = new Intl.NumberFormat('es-GT', {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

/** Small trend line from weekly counts; decorative, the number carries the value.
 * @param {number[]} values
 */
function sparkline(values) {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('viewBox', '0 0 72 24');
  svg.setAttribute('class', 'kpi-spark');
  svg.setAttribute('aria-hidden', 'true');
  if (values.length < 2) return svg;
  const max = Math.max(...values, 1);
  const min = Math.min(...values, 0);
  const span = max - min || 1;
  const points = values
    .map(
      (value, index) =>
        `${(2 + (index * 68) / (values.length - 1)).toFixed(1)},${(22 - ((value - min) / span) * 20).toFixed(1)}`,
    )
    .join(' ');
  const line = document.createElementNS(SVG_NS, 'polyline');
  line.setAttribute('points', points);
  svg.append(line);
  return svg;
}

/** Summary strip above the map: open, in work, resolved and median repair time for the
 * current map area and filters (same scope as the list). Values come from `GET /stats`.
 * @param {HTMLElement} root
 */
export function createMapKpis(root) {
  root.className = 'map-kpis';
  root.setAttribute('aria-label', ui.kpiLabel);
  const cell = (label) => {
    const item = element('div', 'map-kpi');
    const text = element('div', 'map-kpi-text');
    const name = element('span', 'map-kpi-label', label);
    const value = element('span', 'map-kpi-value', '—');
    text.append(name, value);
    item.append(text);
    root.append(item);
    return { item, value };
  };
  root.replaceChildren();
  const open = cell(ui.kpiOpen);
  const work = cell(ui.kpiWork);
  const resolved = cell(ui.kpiResolved);
  const median = cell(ui.kpiMedian);
  return {
    /** @param {object|null} stats */
    render(stats) {
      const weekly = Array.isArray(stats?.weekly) ? stats.weekly : [];
      const count = (value) =>
        Number.isSafeInteger(value) ? String(value) : '—';
      open.value.textContent = count(stats?.abiertos);
      work.value.textContent = count(stats?.by_state_group?.in_work);
      resolved.value.textContent = count(stats?.resueltos);
      const hours = stats?.resolucion_horas?.median;
      median.value.textContent = Number.isFinite(hours)
        ? `${days.format(hours / 24)} d`
        : '—';
      open.item.querySelector('.kpi-spark')?.remove();
      resolved.item.querySelector('.kpi-spark')?.remove();
      open.item.append(sparkline(weekly.map((week) => week.recibidos ?? 0)));
      resolved.item.append(
        sparkline(weekly.map((week) => week.resueltos ?? 0)),
      );
    },
  };
}
