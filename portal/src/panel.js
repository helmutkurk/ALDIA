import { safePhotoUrl } from './api.js';
import { CATEGORIES, categoryLabel } from './categories.js';
import { filterReports } from './state.js';
import { formatDate, RESOLUTIONS, STATUSES, statusLabel, t } from './i18n.js';

/** DOM creation always assigns textContent; no HTML from the API is interpreted.
 * @param {string} tag @param {string} [className] @param {string} [text]
 * @returns {HTMLElement}
 */
export function element(tag, className = '', text = '') {
  const node = document.createElement(tag);
  node.className = className;
  node.textContent = text;
  return node;
}

/** @param {import('./api.js').Report} report */
function statusBadge(report) {
  return element(
    'span',
    `status-badge status-badge--${report.status}`,
    statusLabel(report),
  );
}

/** Shared report details for Leaflet popups. All API fields remain text nodes.
 * @param {import('./api.js').Report} report
 */
export function createReportDetails(report) {
  const details = element('article', 'report-details');
  const heading = element('h2', '', categoryLabel(report.category));
  heading.tabIndex = -1;
  const resolution = element(
    'span',
    `resolution-chip resolution-chip--${report.resolution}`,
    t.resolutions[report.resolution],
  );
  const link = element('a', 'detail-link', t.viewReport);
  link.href = `#/reports/${report.id}`;
  details.append(heading, statusBadge(report), resolution, link);
  const photoUrl = safePhotoUrl(report.photo_url);
  if (photoUrl) {
    const image = document.createElement('img');
    image.className = 'report-photo';
    image.alt = t.photoAlt(categoryLabel(report.category));
    image.loading = 'lazy';
    image.decoding = 'async';
    image.src = photoUrl;
    image.addEventListener(
      'error',
      () => image.replaceWith(element('p', 'muted', t.photoUnavailable)),
      { once: true },
    );
    details.append(image);
  } else details.append(element('p', 'muted', t.photoUnavailable));
  const date = element('p', 'captured-date', `${t.capturedAt}: `);
  const time = document.createElement('time');
  time.dateTime = report.captured_at;
  time.textContent = formatDate(report.captured_at);
  date.append(time);
  details.append(date);
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
      report.verification.mode === 'stub' ? t.stubWarning : t.modelVerification,
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

/**
 * @param {HTMLElement} root
 * @param {{onFiltersChange: (filters: import('./state.js').Filters) => void, onSelect: (id: string) => void, onRetry: () => void}} callbacks
 */
export function createPanel(root, { onFiltersChange, onSelect, onRetry }) {
  root.setAttribute('aria-labelledby', 'portal-title');
  const header = element('header', 'panel-header');
  header.append(element('a', 'brand', t.appName));
  header.querySelector('a').href = '#/';
  const dashboard = element('a', 'dashboard-link', t.dashboard);
  dashboard.href = '#/panel';
  header.append(dashboard);
  const title = element('h1', '', t.portalTitle);
  title.id = 'portal-title';
  header.append(title, element('p', 'muted', t.introduction));
  const filters = element('fieldset', 'filters');
  filters.append(element('legend', 'sr-only', t.filters));
  function select(id, label, allLabel, options) {
    const group = element('div', 'filter-field');
    const labelNode = element('label', '', label);
    labelNode.htmlFor = id;
    const input = document.createElement('select');
    input.id = id;
    input.name = id;
    for (const option of [{ id: '', label: allLabel }, ...options]) {
      const node = document.createElement('option');
      node.value = option.id;
      node.textContent = option.label;
      input.append(node);
    }
    group.append(labelNode, input);
    filters.append(group);
    return input;
  }
  const category = select(
    'category-filter',
    t.category,
    t.allCategories,
    CATEGORIES,
  );
  const status = select(
    'status-filter',
    t.status,
    t.allStatuses,
    STATUSES.map((id) => ({ id, label: t.statuses[id] })),
  );
  const resolution = select(
    'resolution-filter',
    t.resolution,
    t.allResolutions,
    RESOLUTIONS.map((id) => ({ id, label: t.resolutions[id] })),
  );
  const onChange = () =>
    onFiltersChange({
      category: category.value,
      status: status.value,
      resolution: resolution.value,
    });
  category.addEventListener('change', onChange);
  status.addEventListener('change', onChange);
  resolution.addEventListener('change', onChange);
  const results = element('section', 'results');
  results.setAttribute('aria-labelledby', 'reports-title');
  const reportsTitle = element('h2', '', t.reports);
  reportsTitle.id = 'reports-title';
  const announcement = element('p', 'result-count');
  announcement.setAttribute('role', 'status');
  announcement.setAttribute('aria-live', 'polite');
  announcement.setAttribute('aria-atomic', 'true');
  const message = element('div', 'result-message');
  const list = element('ul', 'report-list');
  list.id = 'reports-list';
  list.tabIndex = -1;
  list.setAttribute('aria-labelledby', 'reports-title');
  const limitHint = element('p', 'limit-hint', t.limitHint);
  limitHint.hidden = true;
  const retry = element('button', 'retry-button', t.retry);
  retry.type = 'button';
  retry.addEventListener('click', onRetry);
  results.append(reportsTitle, announcement, message, list, limitHint);
  root.replaceChildren(header, filters, results);
  /** @type {Readonly<import('./state.js').State>|undefined} */
  let previous;
  /** @type {Map<string, HTMLButtonElement>} */
  const buttons = new Map();
  /** @param {Readonly<import('./state.js').State>} state */
  function render(state) {
    root.setAttribute('aria-busy', String(state.phase === 'loading'));
    category.value = state.filters.category;
    status.value = state.filters.status;
    resolution.value = state.filters.resolution;
    const reports = filterReports(state.reports, state.filters);
    announcement.textContent =
      state.phase === 'loading' || state.phase === 'idle'
        ? t.loading
        : state.phase === 'error'
          ? ''
          : t.count(reports.length, state.total);
    message.replaceChildren();
    if (state.phase === 'error') {
      const alert = element('div', 'error-message');
      alert.setAttribute('role', 'alert');
      alert.append(
        element('strong', '', t.errorTitle),
        element('p', '', state.error?.message ?? t.networkError),
      );
      message.append(alert, retry);
    } else if (state.phase === 'success' && !reports.length) {
      message.append(
        element('p', 'empty-title', t.empty),
        element('p', 'muted', t.emptyHelp),
      );
    }
    // Selection changes must not recreate a focused list button.
    if (
      !previous ||
      state.reports !== previous.reports ||
      state.filters !== previous.filters
    ) {
      const focusedId = [...buttons].find(
        ([, button]) => button === document.activeElement,
      )?.[0];
      const previousButtons = new Map(buttons);
      buttons.clear();
      list.replaceChildren();
      for (const report of reports) {
        const item = element('li');
        const button =
          previousButtons.get(report.id) ?? document.createElement('button');
        button.type = 'button';
        button.className = 'report-button';
        button.setAttribute(
          'aria-label',
          t.selectReport(categoryLabel(report.category), statusLabel(report)),
        );
        button.replaceChildren(
          element('strong', 'report-category', categoryLabel(report.category)),
          statusBadge(report),
          element('span', 'report-date', formatDate(report.captured_at)),
        );
        if (!previousButtons.has(report.id))
          button.addEventListener('click', () => onSelect(report.id));
        buttons.set(report.id, button);
        const link = element('a', 'detail-link', t.viewReport);
        link.href = `#/reports/${report.id}`;
        item.append(button, link);
        list.append(item);
      }
      if (focusedId) buttons.get(focusedId)?.focus({ preventScroll: true });
    }
    buttons.forEach((button, id) =>
      button.setAttribute('aria-pressed', String(id === state.selectedId)),
    );
    limitHint.hidden =
      state.phase !== 'success' || state.total <= reports.length;
    previous = state;
  }
  return {
    render,
    destroy() {
      category.removeEventListener('change', onChange);
      status.removeEventListener('change', onChange);
      resolution.removeEventListener('change', onChange);
      retry.removeEventListener('click', onRetry);
      root.replaceChildren();
    },
  };
}
