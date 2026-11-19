import { STATES, STATE_GROUPS, GROUPS } from './states.js';
import { FILTER_KEYS } from './filters.js';
import { CATEGORIES } from './categories.js';
import { RESOLUTIONS, STATUSES, t } from './i18n.js';

/** @typedef {{code: string, message: string}} ErrorDetail */
/** @typedef {{name: string, passed: boolean, detail: string}} VerificationCheck */
/** @typedef {{passed: boolean, mode: 'stub'|'model', checks: VerificationCheck[]}} Verification */
/**
 * @typedef {object} Report
 * @property {string} id
 * @property {string} category
 * @property {number} latitude
 * @property {number} longitude
 * @property {string} captured_at
 * @property {string} created_at
 * @property {'pending'|'verified'|'rejected'} status
 * @property {'open'|'acknowledged'|'fixed'|'closed'} resolution
 * @property {string|null} note
 * @property {string} photo_url
 * @property {Verification|null} verification
 * @property {string} [state]
 * @property {string} [state_group]
 * @property {string|null} [verified_at]
 * @property {string|null} [resolved_at]
 * @property {string|null} [closed_at]
 * @property {string} [state_changed_at]
 * @property {string|null} [assignee]
 * @property {string|null} [duplicate_of]
 * @property {string|null} [public_note]
 * @property {Array<{at: string, actor_role: string, from_state: string|null, to_state: string, public_note: string|null, internal_note?: string|null}>} [events]
 */
/** @typedef {{items: Report[], total: number, limit?: number, offset?: number}} ReportPage */
/** @typedef {[number, number, number, number]} Bbox west, south, east, north */
/** @typedef {{bbox?: Bbox, category?: string, status?: string, resolution?: string, state?: string, state_group?: string, created_from?: string, created_to?: string, assignee?: string, include_old?: string|boolean, sort?: string, offset?: number, delimiter?: 'comma'|'semicolon'}} ReportQuery */

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '/api';
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
export const uuidPattern = new RegExp(`^${UUID}$`, 'i');
const categoryIds = new Set(CATEGORIES.map(({ id }) => id));

/** Client failures have the same error object as HTTP failures in the contract. */
export class ApiError extends Error {
  /** @param {ErrorDetail} error @param {number} [status] */
  constructor(error, status = 0) {
    super(error.message);
    this.name = 'ApiError';
    this.error = Object.freeze({ code: error.code, message: error.message });
    this.status = status;
  }
}

/** @param {string} baseUrl */
function apiBase(baseUrl) {
  const base = new URL(
    baseUrl.replace(/\/+$/, '') + '/',
    globalThis.location?.origin ?? 'http://localhost',
  );
  if (
    !['http:', 'https:'].includes(base.protocol) ||
    base.username ||
    base.password ||
    base.search ||
    base.hash
  ) {
    throw new TypeError(
      'API base URL must be an HTTP(S) URL or an absolute path without credentials, query or fragment.',
    );
  }
  return base;
}

/**
 * Accept only photo endpoints belonging to the configured API. This also prevents
 * arbitrary external image requests from untrusted report data.
 * @param {string} value
 * @param {string} [baseUrl]
 * @returns {string|null}
 */
export function safePhotoUrl(value, baseUrl = API_BASE_URL) {
  try {
    const base = apiBase(baseUrl);
    const url = new URL(value, base.origin);
    const prefix = `${base.pathname}reports/`;
    const suffix = url.pathname.slice(prefix.length);
    return url.origin === base.origin &&
      !url.username &&
      !url.password &&
      !url.search &&
      !url.hash &&
      url.pathname.startsWith(prefix) &&
      new RegExp(`^${UUID}/(?:photo|thumbnail)$`, 'i').test(suffix)
      ? url.href
      : null;
  } catch {
    return null;
  }
}

/** @param {unknown} value @returns {value is ErrorDetail} */
function isErrorDetail(value) {
  return (
    value !== null &&
    typeof value === 'object' &&
    typeof value.code === 'string' &&
    typeof value.message === 'string'
  );
}

/** @param {unknown} value */
function isTimestamp(value) {
  return (
    typeof value === 'string' &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value) &&
    Number.isFinite(Date.parse(value))
  );
}

/** @param {unknown} value @returns {value is Report} */
function isReport(value) {
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
            ['system', 'operator', 'supervisor'].includes(e.actor_role) &&
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
        ['stub', 'model'].includes(v.mode) &&
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

/**
 * @param {{baseUrl?: string, fetchImpl?: typeof fetch, timeoutMs?: number, staff?: {getToken: () => string}|null}} [options]
 */
export function createApiClient({
  baseUrl = API_BASE_URL,
  fetchImpl = globalThis.fetch,
  timeoutMs = 15000,
  staff = null,
} = {}) {
  const base = apiBase(baseUrl);
  /** @param {string} path @param {ReportQuery} query */
  function filteredUrl(path, query) {
    const url = new URL(path, base);
    if (query.bbox) url.searchParams.set('bbox', query.bbox.join(','));
    for (const name of FILTER_KEYS.filter((key) => key !== 'bbox')) {
      if (query[name]) url.searchParams.set(name, query[name]);
    }
    return url;
  }
  /** Shared deadlines, cancellation and contract-shaped errors for all reads.
   * @param {URL} url @param {(body: unknown) => boolean} validate
   * @param {{signal?: AbortSignal}} [options]
   */
  async function request(
    url,
    validate,
    { signal, method = 'GET', body: payload, responseType = 'json' } = {},
  ) {
    const controller = new AbortController();
    const abort = () => controller.abort(signal.reason);
    if (signal?.aborted) throw signal.reason;
    signal?.addEventListener('abort', abort, { once: true });
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, timeoutMs);
    try {
      const response = await fetchImpl(url.href, {
        signal: controller.signal,
        method,
        headers: {
          Accept:
            responseType === 'blob'
              ? 'text/csv'
              : responseType === 'photo'
                ? 'image/jpeg, image/png'
                : 'application/json',
          ...(payload ? { 'Content-Type': 'application/json' } : {}),
          ...(staff?.getToken() ? { 'X-Staff-Token': staff.getToken() } : {}),
        },
        ...(payload ? { body: JSON.stringify(payload) } : {}),
        cache: 'no-store',
        credentials: 'omit',
        referrerPolicy: 'strict-origin-when-cross-origin',
        redirect: 'error',
      });
      let body;
      try {
        body =
          response.ok && responseType !== 'json'
            ? await response.blob()
            : response.status === 204
              ? null
              : await response.json();
      } catch {
        if (controller.signal.aborted) throw controller.signal.reason;
        if (response.ok)
          throw new ApiError(
            { code: 'invalid_response', message: t.invalidResponse },
            response.status,
          );
      }
      if (!response.ok) {
        throw new ApiError(
          isErrorDetail(body?.error)
            ? body.error
            : { code: 'http_error', message: t.httpError(response.status) },
          response.status,
        );
      }
      if (!validate(body))
        throw new ApiError(
          { code: 'invalid_response', message: t.invalidResponse },
          response.status,
        );
      return body;
    } catch (error) {
      if (signal?.aborted) throw signal.reason;
      if (timedOut)
        throw new ApiError({ code: 'timeout', message: t.timeoutError });
      if (error instanceof ApiError) throw error;
      throw new ApiError({ code: 'network_error', message: t.networkError });
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    }
  }
  return {
    /** @param {ReportQuery} query @param {{signal?: AbortSignal}} [options] @returns {Promise<ReportPage>} */
    getReports(query, options) {
      const url = filteredUrl('reports', query);
      url.searchParams.set('limit', '25');
      if (query.offset) url.searchParams.set('offset', String(query.offset));
      return request(
        url,
        (body) =>
          Boolean(
            body &&
            Array.isArray(body.items) &&
            Number.isSafeInteger(body.total) &&
            body.total >= body.items.length &&
            body.items.length <= 25 &&
            body.items.every(isReport) &&
            new Set(body.items.map(({ id }) => id)).size === body.items.length,
          ),
        options,
      );
    },
    /** @param {string} id @param {{signal?: AbortSignal}} [options] @returns {Promise<Report>} */
    getReport(id, options) {
      if (!uuidPattern.test(id))
        throw new TypeError('Report ID must be a UUID.');
      return request(
        new URL(`reports/${id}`, base),
        (body) => isReport(body) && body.id.toLowerCase() === id.toLowerCase(),
        options,
      );
    },
    /** @param {object} query @param {object} [options] */
    getClusters(query, options) {
      const url = filteredUrl('reports/clusters', query);
      url.searchParams.set('zoom', String(query.zoom));
      return request(
        url,
        (body) =>
          body &&
          Number.isSafeInteger(body.total) &&
          body.total >= 0 &&
          Array.isArray(body.clusters) &&
          body.clusters.length <= 500 &&
          body.clusters.every(
            (c) =>
              c &&
              Number.isFinite(c.lat) &&
              Math.abs(c.lat) <= 90 &&
              Number.isFinite(c.lon) &&
              Math.abs(c.lon) <= 180 &&
              Number.isSafeInteger(c.count) &&
              c.count > 0 &&
              (c.ids === undefined ||
                (Array.isArray(c.ids) &&
                  c.ids.every((id) => uuidPattern.test(id)))),
          ),
        options,
      );
    },
    /** @param {string} id @param {object} [options] */
    getNearby(id, options) {
      if (!uuidPattern.test(id))
        throw new TypeError('Report ID must be a UUID.');
      return request(
        new URL(`reports/${id}/nearby`, base),
        (body) =>
          Array.isArray(body) && body.length <= 10 && body.every(isReport),
        options,
      );
    },
    /** @param {'review'|'rejected'} tab @param {object} query @param {object} [options] */
    getQueue(tab, query = {}, options) {
      const url = new URL('queue', base);
      url.searchParams.set('tab', tab);
      url.searchParams.set('limit', '25');
      if (query.offset) url.searchParams.set('offset', String(query.offset));
      return request(
        url,
        (body) =>
          body &&
          Array.isArray(body.items) &&
          body.items.length <= 25 &&
          body.items.every(isReport) &&
          Number.isSafeInteger(body.total) &&
          body.total >= body.items.length,
        options,
      );
    },
    /** @param {string} id @param {object} body @param {object} [options] */
    transition(id, body, options) {
      if (!uuidPattern.test(id))
        throw new TypeError('Report ID must be a UUID.');
      return request(new URL(`reports/${id}/transition`, base), isReport, {
        ...options,
        method: 'POST',
        body,
      });
    },
    /** Assignment response is not specified: both an empty success and a report are accepted.
     * @param {string} id @param {string|null} assignee @param {object} [options] */
    assign(id, assignee, options) {
      if (!uuidPattern.test(id))
        throw new TypeError('Report ID must be a UUID.');
      return request(
        new URL(`reports/${id}/assign`, base),
        (body) => body === null || (body && typeof body === 'object'),
        { ...options, method: 'POST', body: { assignee } },
      );
    },
    /** @param {ReportQuery} query @param {{signal?: AbortSignal}} [options] @returns {Promise<Stats>} */
    getStats(query, options) {
      return request(filteredUrl('stats', query), isStats, options);
    },
    hasStaff: () => Boolean(staff?.getToken()),
    /** @param {string} value @param {object} [options] */
    getPhotoBlob(value, options) {
      const url = safePhotoUrl(value, baseUrl);
      if (!url)
        throw new TypeError('Photo URL must belong to the configured API.');
      return request(
        new URL(url),
        (body) =>
          body &&
          body.size > 0 &&
          ['image/jpeg', 'image/png'].includes(body.type),
        { ...options, responseType: 'photo' },
      );
    },
    /** CSV requests share the same token, cancellation and deadline as JSON reads.
     * @param {ReportQuery} query @param {object} [options] */
    getCsvBlob(query, options) {
      return request(
        new URL(this.getCsvUrl(query)),
        (body) => body && typeof body.size === 'number',
        { ...options, responseType: 'blob' },
      );
    },
    /** @param {ReportQuery} query @returns {string} */
    getCsvUrl(query) {
      const url = filteredUrl('reports.csv', query);
      if (['comma', 'semicolon'].includes(query.delimiter))
        url.searchParams.set('delimiter', query.delimiter);
      return url.href;
    },
  };
}

/** @typedef {{total: number, by_category: Object<string, number>, by_status: Object<string, number>, by_resolution: Object<string, number>}} Stats */
/** @param {unknown} body @returns {body is Stats} */
function isStats(body) {
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
