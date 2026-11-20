import { element } from './dom.js';
import { createPhoto } from './photo.js';
import { categoryLabel } from './categories.js';
import { reportState, stateLabel, STATE_GROUPS } from './states.js';
import { formatDate, statusLabel, t } from './i18n.js';

/** @param {import('./api.js').Report} report */
export function statusBadge(report) {
  return element(
    'span',
    `status-badge status-badge--${report.status}`,
    statusLabel(report),
  );
}

/** Shared report details for Leaflet popups. All API fields remain text nodes.
 * @param {import('./api.js').Report} report
 */
export function createReportDetails(report, photoOptions = {}) {
  const details = element('article', 'report-details');
  const heading = element('h2', '', categoryLabel(report.category));
  heading.tabIndex = -1;
  const resolution = element(
    'span',
    `resolution-chip resolution-chip--${report.resolution}`,
    t.resolutions[report.resolution],
  );
  const link = element('a', 'detail-link', t.viewReport);
  link.textContent = 'Ver reporte e historial';
  link.href = `#/reports/${report.id}`;
  const state = reportState(report);
  details.append(
    heading,
    statusBadge(report),
    resolution,
    element(
      'span',
      `state-chip state-chip--${STATE_GROUPS[state]}`,
      stateLabel(state),
    ),
    link,
  );
  details.append(createPhoto(report, photoOptions));
  const date = element('p', 'captured-date', `${t.capturedAt}: `);
  const time = document.createElement('time');
  time.dateTime = report.captured_at;
  time.textContent = formatDate(report.captured_at);
  date.append(time);
  details.append(date);
  if (report.public_note)
    details.append(element('p', 'public-note', report.public_note));
  if (report.note) details.append(element('p', 'report-note', report.note));
  details.append(element('h3', '', t.verification));
  if (!report.verification) {
    details.append(element('p', '', t.verificationPending));
    return details;
  }
  details.append(
    element(
      'p',
      report.verification.mode === 'stub' ? 'stub-warning' : 'muted',
      report.verification.mode === 'stub'
        ? t.stubWarning
        : report.verification.mode === 'heuristic'
          ? t.heuristicVerification
          : t.modelVerification,
    ),
  );
  if (!report.verification.checks.length)
    details.append(element('p', 'muted', t.noChecks));
  const checks = element('ul', 'verification-checks');
  for (const check of report.verification.checks) {
    const item = element('li');
    const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    icon.setAttribute('viewBox', '0 0 24 24');
    icon.setAttribute('class', 'check-icon');
    icon.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute(
      'd',
      check.passed ? 'M4 12l5 5L20 6' : 'M6 6l12 12M18 6L6 18',
    );
    icon.append(path);
    item.append(
      icon,
      element(
        'strong',
        '',
        `${Object.hasOwn(t.checks, check.name) ? t.checks[check.name] : check.name}: ${check.passed ? t.passed : t.failed}`,
      ),
    );
    if (check.detail)
      item.append(element('span', 'check-detail', check.detail));
    checks.append(item);
  }
  details.append(checks);
  return details;
}
