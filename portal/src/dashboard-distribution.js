import { element } from './dom.js';
import { t } from './i18n.js';
import { chartPatterns } from './chart-patterns.js';
import { quantity } from './dashboard-metrics.js';

export function categoryTable(rows, visibleGroups, listLink) {
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
    const stack = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
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
    const patterns = chartPatterns(stack);
    const fills = {
      pending: patterns.outline,
      open: patterns.diagonal,
      in_work: patterns.horizontal,
      resolved: patterns.solid,
      closed: patterns.dots,
      hidden: patterns.cross,
    };
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
      rect.setAttribute('fill', fills[group]);
      rect.setAttribute('stroke', 'var(--primary)');
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
