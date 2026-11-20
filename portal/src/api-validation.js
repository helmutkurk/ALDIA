import { STATES, STATE_GROUPS, GROUPS } from './states.js';
import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES } from './i18n.js';
export const UUID =
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
export const uuidPattern = new RegExp(`^${UUID}$`, 'i');
const categoryIds = new Set(CATEGORIES.map(({ id }) => id));

/** @param {unknown} value */
function isTimestamp(value) {
  return (
    typeof value === 'string' &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value) &&
    Number.isFinite(Date.parse(value))
  );
}

/** @param {unknown} value @returns {value is Report} */
export function isReport(value) {
  if (value === null || typeof value !== 'object') return false;
  const v = value.verification;
  return (
    typeof value.id === 'string' &&
    uuidPattern.test(value.id) &&
    categoryIds.has(value.category) &&
    (value.state === undefined ||
      (STATES.includes(value.state) &&
        value.state_group === STATE_GROUPS[value.state])) &&
    [
      'verified_at',
      'state_changed_at',
      'resolved_at',
      'closed_at',
      'assigned_at',
    ].every(
      (key) =>
        value[key] === undefined ||
        value[key] === null ||
        isTimestamp(value[key]),
    ) &&
    ['assignee', 'public_note'].every(
      (key) =>
        value[key] === undefined ||
        value[key] === null ||
        typeof value[key] === 'string',
    ) &&
    (value.duplicate_of === undefined ||
      value.duplicate_of === null ||
      uuidPattern.test(value.duplicate_of)) &&
    (value.age_hours === undefined ||
      (Number.isFinite(value.age_hours) && value.age_hours >= 0)) &&
    (value.events === undefined ||
      (Array.isArray(value.events) &&
        value.events.every(
          (e) =>
            e &&
            isTimestamp(e.at) &&
            ['system', 'operator', 'supervisor', 'admin'].includes(
              e.actor_role,
            ) &&
            (e.actor === undefined || typeof e.actor === 'string') &&
            (e.from_state === null || STATES.includes(e.from_state)) &&
            STATES.includes(e.to_state) &&
            (e.public_note === null || typeof e.public_note === 'string') &&
            (e.internal_note === undefined ||
              e.internal_note === null ||
              typeof e.internal_note === 'string'),
        ))) &&
    STATUSES.includes(value.status) &&
    RESOLUTIONS.includes(value.resolution) &&
    Number.isFinite(value.latitude) &&
    Math.abs(value.latitude) <= 90 &&
    Number.isFinite(value.longitude) &&
    Math.abs(value.longitude) <= 180 &&
    isTimestamp(value.captured_at) &&
    isTimestamp(value.created_at) &&
    (value.note === null || typeof value.note === 'string') &&
    typeof value.photo_url === 'string' &&
    (v === null
      ? value.status === 'pending'
      : typeof v === 'object' &&
        ['stub', 'heuristic', 'model'].includes(v.mode) &&
        typeof v.passed === 'boolean' &&
        Array.isArray(v.checks) &&
        v.checks.every(
          (check) =>
            check !== null &&
            typeof check === 'object' &&
            typeof check.name === 'string' &&
            typeof check.passed === 'boolean' &&
            typeof check.detail === 'string',
        ))
  );
}

/** @typedef {{total: number, by_category: Object<string, number>, by_status: Object<string, number>, by_resolution: Object<string, number>}} Stats */
/** @param {unknown} body @returns {body is Stats} */
export function isStats(body) {
  if (!body || !Number.isSafeInteger(body.total) || body.total < 0)
    return false;
  if (body.recibidos !== undefined && !isMunicipalStats(body)) return false;
  return [
    ['by_category', [...categoryIds]],
    ['by_status', STATUSES],
    ['by_resolution', RESOLUTIONS],
  ].every(([key, ids]) => {
    const counts = body[key];
    return (
      counts &&
      typeof counts === 'object' &&
      !Array.isArray(counts) &&
      Object.entries(counts).every(
        ([id, count]) =>
          ids.includes(id) && Number.isSafeInteger(count) && count >= 0,
      ) &&
      Object.values(counts).reduce((sum, count) => sum + count, 0) ===
        body.total
    );
  });
}

/** Validate additive metrics without manufacturing missing samples or treating null as zero.
 * @param {object} body
 */
function isMunicipalStats(body) {
  const count = (value) => Number.isSafeInteger(value) && value >= 0;
  const duration = (value) =>
    value === null || (Number.isFinite(value) && value >= 0);
  const ratio = (value) =>
    value === null || (Number.isFinite(value) && value >= 0 && value <= 1);
  const histogram = (value, keys) =>
    value &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    Object.entries(value).every(([key, n]) => keys.includes(key) && count(n));
  return (
    [
      'recibidos',
      'rechazados_verificador',
      'abiertos',
      'resueltos',
      'cerrados_sin_solucion',
      'vencidos',
    ].every((key) => count(body[key])) &&
    ratio(body.tasa_resolucion) &&
    ratio(body.sla_cumplido) &&
    body.resolucion_horas &&
    ['median', 'p90', 'mean'].every((key) =>
      duration(body.resolucion_horas[key]),
    ) &&
    count(body.resolucion_horas.n) &&
    body.primera_respuesta_horas &&
    ['median', 'p90'].every((key) =>
      duration(body.primera_respuesta_horas[key]),
    ) &&
    count(body.primera_respuesta_horas.n) &&
    histogram(body.antiguedad_abiertos, ['0-2', '3-7', '8-30', '>30']) &&
    histogram(body.by_state, STATES) &&
    histogram(body.by_state_group, GROUPS) &&
    Array.isArray(body.weekly) &&
    body.weekly.every(
      (item) =>
        item &&
        /^\d{4}-W(?:0[1-9]|[1-4]\d|5[0-3])$/.test(item.week) &&
        count(item.recibidos) &&
        count(item.resueltos),
    )
  );
}
