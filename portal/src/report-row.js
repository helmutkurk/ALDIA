import { element } from './dom.js';
import { categoryIcon, categoryLabel } from './categories.js';
import { formatDate, t } from './i18n.js';
import { STATE_GROUPS, reportState, stateLabel } from './states.js';
import { statusBadge } from './report-details.js';
import { createPhoto } from './photo.js';

const relative = new Intl.RelativeTimeFormat('es', { numeric: 'always' });
/** Use elapsed days, hours or minutes; preserve the exact local date in the tooltip. */
export function relativeDate(value, now = Date.now()) {
  const elapsed = new Date(value).getTime() - now;
  if (!Number.isFinite(elapsed)) return t.unknownDate;
  for (const [unit, ms] of [
    ['day', 86400000],
    ['hour', 3600000],
    ['minute', 60000],
  ]) {
    if (Math.abs(elapsed) >= ms)
      return relative.format(Math.trunc(elapsed / ms), unit);
  }
  return 'hace un momento';
}

/** Only the row contents change: the parent retains its focused selection button. */
export function reportRow(report, { api, signal }) {
  const category = element('strong', 'report-category');
  category.append(
    categoryIcon(report.category),
    document.createTextNode(categoryLabel(report.category)),
  );
  const date = element('time', 'report-date', relativeDate(report.captured_at));
  date.dateTime = report.captured_at;
  date.title = formatDate(report.captured_at);
  return [
    category,
    date,
    element(
      'span',
      `state-chip state-chip--${STATE_GROUPS[reportState(report)]}`,
      stateLabel(reportState(report)),
    ),
    element('span', 'report-snippet', report.note ?? report.public_note ?? ''),
    statusBadge(report),
    createPhoto(report, {
      api,
      signal,
      thumbnail: true,
      quiet: true,
      className: 'row-thumbnail',
    }),
  ];
}
