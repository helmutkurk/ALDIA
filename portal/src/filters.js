import { CATEGORIES } from './categories.js';
import { GROUPS, STATES } from './states.js';
import { RESOLUTIONS, STATUSES } from './i18n.js';

export const FILTER_KEYS = Object.freeze([
  'bbox',
  'category',
  'status',
  'resolution',
  'state_group',
  'state',
  'created_from',
  'created_to',
  'assignee',
  'sort',
  'include_old',
]);
export const SORTS = Object.freeze([
  'newest',
  'oldest',
  'updated',
  'age_in_state',
]);
/** Decode only public contract filters. Tokens and arbitrary hash fields are discarded.
 * @param {string} hash
 */
export function parseFilters(hash) {
  const params = new URLSearchParams(hash.split('?')[1] ?? '');
  const result = {};
  for (const key of FILTER_KEYS) {
    const value = params.get(key);
    if (!value) continue;
    const enums = {
      category: CATEGORIES.map((c) => c.id),
      status: STATUSES,
      resolution: RESOLUTIONS,
      state: STATES,
      state_group: GROUPS,
      sort: SORTS,
      include_old: ['true'],
    };
    if (enums[key] && !enums[key].includes(value)) continue;
    if (
      key.startsWith('created_') &&
      (!/^\d{4}-\d{2}-\d{2}$/.test(value) ||
        !Number.isFinite(Date.parse(value)) ||
        new Date(value).toISOString().slice(0, 10) !== value)
    )
      continue;
    if (key === 'assignee' && value.length > 60) continue;
    if (key === 'bbox') {
      const bounds = value.split(',').map(Number);
      if (
        bounds.length !== 4 ||
        bounds.some((v) => !Number.isFinite(v)) ||
        bounds[0] < -180 ||
        bounds[2] > 180 ||
        bounds[1] < -90 ||
        bounds[3] > 90 ||
        bounds[0] >= bounds[2] ||
        bounds[1] >= bounds[3]
      )
        continue;
      result.bbox = bounds;
    } else result[key] = value;
  }
  return result;
}
/** @param {string} path @param {object} filters */
export function filtersHash(path = '#/', filters = {}) {
  const params = new URLSearchParams();
  for (const key of FILTER_KEYS) {
    const value = filters[key];
    if (
      value !== undefined &&
      value !== '' &&
      value !== false &&
      value !== null
    )
      params.set(key, Array.isArray(value) ? value.join(',') : String(value));
  }
  return path + (params.size ? `?${params}` : '');
}
