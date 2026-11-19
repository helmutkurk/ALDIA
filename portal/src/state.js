import { parseFilters, filtersHash } from './filters.js';
import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES } from './i18n.js';

/** @typedef {{category: string, status: string, resolution: string}} Filters */
/**
 * @typedef {object} State
 * @property {ReadonlyArray<import('./api.js').Report>} reports
 * @property {number} total
 * @property {Readonly<Filters>} filters
 * @property {'idle'|'loading'|'success'|'error'} phase
 * @property {import('./api.js').ErrorDetail|null} error
 * @property {string|null} selectedId
 */

/** @param {ReadonlyArray<import('./api.js').Report>} reports @param {Filters} filters */
export function filterReports(
  reports,
  { category, status, resolution, state, state_group, assignee },
) {
  return reports.filter(
    (report) =>
      (!category || report.category === category) &&
      (!status || report.status === status) &&
      (!resolution || report.resolution === resolution) &&
      (!state || report.state === state) &&
      (!state_group || report.state_group === state_group) &&
      (!assignee || report.assignee === assignee),
  );
}

/** A small synchronous store. Subscribers receive immutable snapshots immediately. */
export function createStore() {
  /** @type {Readonly<State>} */
  let state = Object.freeze({
    reports: Object.freeze([]),
    total: 0,
    offset: 0,
    filters: Object.freeze({ category: '', status: '', resolution: '' }),
    phase: 'idle',
    error: null,
    selectedId: null,
  });
  /** @type {Set<(state: Readonly<State>) => void>} */
  const listeners = new Set();
  /** @param {Partial<State>} patch */
  function update(patch) {
    state = Object.freeze({ ...state, ...patch });
    listeners.forEach((listener) => listener(state));
  }
  return {
    getState: () => state,
    /** @param {(state: Readonly<State>) => void} listener */
    subscribe(listener) {
      listeners.add(listener);
      listener(state);
      return () => listeners.delete(listener);
    },
    /** @param {Filters} filters */
    setFilters(filters) {
      filters = { resolution: '', ...filters };
      if (
        (filters.category &&
          !CATEGORIES.some(({ id }) => id === filters.category)) ||
        (filters.status && !STATUSES.includes(filters.status)) ||
        (filters.resolution && !RESOLUTIONS.includes(filters.resolution))
      ) {
        throw new RangeError(
          'Filters must use contract category, status and resolution IDs.',
        );
      }
      const parsed = parseFilters(filtersHash('#/', filters));
      for (const [key, value] of Object.entries(filters)) {
        if (value && key !== 'bbox' && parsed[key] !== String(value))
          throw new RangeError('Invalid contract filter.');
      }
      if (JSON.stringify(filters) === JSON.stringify(state.filters)) return;
      update({
        filters: Object.freeze({ ...filters }),
        offset: 0,
        reports: Object.freeze([]),
        total: 0,
        selectedId: null,
        error: null,
        phase: 'loading',
      });
    },
    setOffset(offset) {
      update({ offset: Math.max(0, offset), selectedId: null });
    },
    startLoading: () => update({ phase: 'loading', error: null }),
    /** @param {import('./api.js').ReportPage} page */
    setReports({ items, total }) {
      update({
        reports: Object.freeze([...items]),
        total,
        phase: 'success',
        error: null,
        selectedId: items.some(({ id }) => id === state.selectedId)
          ? state.selectedId
          : null,
      });
    },
    /** @param {import('./api.js').ErrorDetail} error */
    setError(error) {
      update({
        phase: 'error',
        error,
        reports: Object.freeze([]),
        total: 0,
        selectedId: null,
      });
    },
    /** @param {string|null} id */
    selectReport(id) {
      update({
        selectedId: state.reports.some((report) => report.id === id)
          ? id
          : null,
      });
    },
  };
}
