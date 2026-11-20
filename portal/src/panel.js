import {
  STATES,
  GROUPS,
  stateLabel,
  reportState,
  STATE_GROUPS,
} from './states.js';
import { SORTS, filtersHash } from './filters.js';
import { ui } from './i18n.js';
import { element } from './dom.js';
import { reportRow } from './report-row.js';
import { mobileFilters } from './mobile-filters.js';
export { element } from './dom.js';
export { createReportDetails } from './report-details.js';
import { CATEGORIES, categoryLabel } from './categories.js';
import { filterReports } from './state.js';
import { RESOLUTIONS, STATUSES, statusLabel, t } from './i18n.js';

/**
 * @param {HTMLElement} root
 * @param {{onFiltersChange: (filters: import('./state.js').Filters) => void, onSelect: (id: string) => void, onRetry: () => void}} callbacks
 */
export function createPanel(
  root,
  { onFiltersChange, onSelect, onRetry, onPage = () => {}, getScope, api },
) {
  root.setAttribute('aria-labelledby', 'portal-title');
  const header = element('header', 'panel-header');
  const title = element('h1', '', t.portalTitle);
  title.id = 'portal-title';
  header.append(
    title,
    element('p', 'panel-place', `${ui.panelBanner} · ${t.city}`),
  );
  const filters = element('fieldset', 'filters');
  filters.append(element('legend', 'sr-only', t.filters));
  // The four filters of the reference layout stay visible; the rest sit in a disclosure.
  const mainFilters = element('div', 'filters-main');
  const moreFilters = element('details', 'filters-more');
  moreFilters.append(element('summary', '', ui.moreFilters));
  const moreBody = element('div', 'filters-more-body');
  moreFilters.append(moreBody);
  filters.append(mainFilters, moreFilters);
  function select(id, label, allLabel, options, target = moreBody) {
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
    target.append(group);
    return input;
  }
  const category = select(
    'category-filter',
    t.category,
    t.allCategories,
    CATEGORIES,
    mainFilters,
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
  const group = select(
    'state-group-filter',
    ui.statusFilter,
    ui.allGroups,
    GROUPS.map((id) => ({ id, label: ui.groups[id] })),
    mainFilters,
  );
  const stateInput = select(
    'state-filter',
    ui.state,
    ui.allStates,
    STATES.map((id) => ({ id, label: stateLabel(id) })),
  );
  const sort = select(
    'sort-filter',
    ui.sort,
    ui.sorts.newest,
    SORTS.filter((id) => id !== 'newest').map((id) => ({
      id,
      label: ui.sorts[id],
    })),
    mainFilters,
  );
  mainFilters.prepend(group.parentElement);
  const controls = {
    category,
    status,
    resolution,
    state_group: group,
    state: stateInput,
    sort,
  };
  for (const [name, label, type] of [
    ['created_from', ui.from, 'date'],
    ['created_to', ui.to, 'date'],
    ['assignee', ui.assignee, 'text'],
    ['include_old', ui.includeOldLong, 'checkbox'],
  ]) {
    const labelNode = element(
      'label',
      name === 'include_old' ? 'filter-field filter-check' : 'filter-field',
      label,
    );
    const input = element('input');
    input.type = type;
    input.name = name;
    if (name === 'assignee') input.maxLength = 60;
    labelNode.append(input);
    (name === 'include_old' ? mainFilters : moreBody).append(labelNode);
    controls[name] = input;
  }
  const chips = element('div', 'filter-chips');
  const onChange = (event) => {
    if (
      event.target === group &&
      stateInput.value &&
      STATE_GROUPS[stateInput.value] !== group.value
    )
      stateInput.value = '';
    if (
      event.target === stateInput &&
      stateInput.value &&
      group.value &&
      STATE_GROUPS[stateInput.value] !== group.value
    )
      group.value = STATE_GROUPS[stateInput.value];
    const next = {
      category: category.value,
      status: status.value,
      resolution: resolution.value,
    };
    for (const [key, input] of Object.entries(controls)) {
      const value =
        input.type === 'checkbox' ? (input.checked ? 'true' : '') : input.value;
      if (value) next[key] = value;
    }
    onFiltersChange(next);
  };
  filters.addEventListener('change', onChange, true);
  moreBody.append(element('p', 'muted filters-hint', ui.defaultWindow));
  const pagination = element('nav', 'pagination');
  pagination.setAttribute('aria-label', ui.page(1, 0));
  const previousPage = element('button', '', ui.previous);
  previousPage.type = 'button';
  const nextPage = element('button', '', ui.next);
  nextPage.type = 'button';
  const pageLabel = element('span');
  previousPage.addEventListener('click', () =>
    onPage(Math.max(0, (previous?.offset ?? 0) - 25)),
  );
  nextPage.addEventListener('click', () =>
    onPage((previous?.offset ?? 0) + 25),
  );
  pagination.append(previousPage, pageLabel, nextPage);
  const results = element('section', 'results');
  results.setAttribute('aria-labelledby', 'reports-title');
  const reportsTitle = element('h2', 'sr-only', t.reports);
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
  const retry = element('button', 'retry-button', t.retry);
  retry.type = 'button';
  retry.addEventListener('click', onRetry);
  results.append(reportsTitle, announcement, message, list);
  const sheet = mobileFilters(filters);
  root.replaceChildren(header, ...sheet.nodes, chips, results, pagination);
  /** @type {Readonly<import('./state.js').State>|undefined} */
  let previous;
  let photos = new AbortController();
  /** @type {Map<string, HTMLButtonElement>} */
  const buttons = new Map();
  /** @param {Readonly<import('./state.js').State>} state */
  function render(state) {
    root.setAttribute('aria-busy', String(state.phase === 'loading'));
    category.value = state.filters.category;
    status.value = state.filters.status;
    resolution.value = state.filters.resolution;
    for (const [key, input] of Object.entries(controls)) {
      if (input.type === 'checkbox')
        input.checked = state.filters[key] === 'true';
      else input.value = state.filters[key] ?? '';
    }
    const active = Object.entries(state.filters).filter(
      ([key, value]) => value && key !== 'bbox',
    );
    chips.hidden = active.length === 0;
    chips.replaceChildren();
    for (const [key, value] of active) {
      const label =
        key === 'state'
          ? stateLabel(value)
          : key === 'state_group'
            ? ui.groups[value]
            : key === 'category'
              ? categoryLabel(value)
              : key === 'sort'
                ? ui.sorts[value]
                : key === 'include_old'
                  ? ui.includeOld
                  : value;
      const chip = element('button', '', `${label} ×`);
      chip.type = 'button';
      chip.setAttribute('aria-label', ui.removeFilter(label));
      chip.addEventListener('click', () => {
        const next = { ...state.filters };
        delete next[key];
        onFiltersChange(next);
      });
      chips.append(chip);
    }
    pageLabel.textContent = ui.page(
      Math.floor((state.offset ?? 0) / 25) + 1,
      state.total,
    );
    previousPage.disabled = !(state.offset > 0);
    nextPage.disabled =
      (state.offset ?? 0) + 25 >= state.total || state.phase !== 'success';
    const reports = filterReports(state.reports, state.filters);
    announcement.textContent =
      state.phase === 'loading' || state.phase === 'idle'
        ? t.loading
        : state.phase === 'error'
          ? ''
          : reports.length
            ? ui.range(
                (state.offset ?? 0) + 1,
                (state.offset ?? 0) + reports.length,
                state.total,
              )
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
      photos.abort();
      photos = new AbortController();
      list.replaceChildren();
      for (const report of reports) {
        const item = element('li');
        const button =
          previousButtons.get(report.id) ?? document.createElement('button');
        button.type = 'button';
        button.className = 'report-button';
        button.setAttribute(
          'aria-label',
          t.selectReport(
            categoryLabel(report.category),
            `${stateLabel(reportState(report))}. ${statusLabel(report)}`,
          ),
        );
        button.replaceChildren(
          ...reportRow(report, { api, signal: photos.signal }),
        );
        if (!previousButtons.has(report.id))
          button.addEventListener('click', () => onSelect(report.id));
        buttons.set(report.id, button);
        const link = element('a', 'detail-link', t.viewReport);
        link.href = filtersHash(
          `#/reports/${report.id}`,
          getScope?.() ?? state.filters,
        );
        item.append(button, link);
        list.append(item);
      }
      if (focusedId) buttons.get(focusedId)?.focus({ preventScroll: true });
    }
    buttons.forEach((button, id) =>
      button.setAttribute('aria-pressed', String(id === state.selectedId)),
    );
    previous = state;
  }
  return {
    render,
    destroy() {
      sheet.destroy();
      photos.abort();
      filters.removeEventListener('change', onChange, true);
      retry.removeEventListener('click', onRetry);
      root.replaceChildren();
    },
  };
}
