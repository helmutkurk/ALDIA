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
 * @property {'open'|'acknowledged'|'fixed'} resolution
 * @property {string|null} note
 * @property {string} photo_url
 * @property {Verification|null} verification
 */
/** @typedef {{items: Report[], total: number}} ReportPage */
/** @typedef {[number, number, number, number]} Bbox west, south, east, north */
/** @typedef {{bbox?: Bbox, category?: string, status?: string, resolution?: string}} ReportQuery */

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
      new RegExp(`^${UUID}/photo$`, 'i').test(suffix)
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
 * @param {{baseUrl?: string, fetchImpl?: typeof fetch, timeoutMs?: number}} [options]
 */
export function createApiClient({
  baseUrl = API_BASE_URL,
  fetchImpl = globalThis.fetch,
  timeoutMs = 15000,
} = {}) {
  const base = apiBase(baseUrl);
  /** @param {string} path @param {ReportQuery} query */
  function filteredUrl(path, query) {
    const url = new URL(path, base);
    if (query.bbox) url.searchParams.set('bbox', query.bbox.join(','));
    for (const name of ['category', 'status', 'resolution']) {
      if (query[name]) url.searchParams.set(name, query[name]);
    }
    return url;
  }
  /** Shared deadlines, cancellation and contract-shaped errors for all reads.
   * @param {URL} url @param {(body: unknown) => boolean} validate
   * @param {{signal?: AbortSignal}} [options]
   */
  async function request(url, validate, { signal } = {}) {
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
        headers: { Accept: 'application/json' },
        credentials: 'omit',
        referrerPolicy: 'strict-origin-when-cross-origin',
      });
      let body;
      try {
        body = await response.json();
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
      url.searchParams.set('limit', '500');
      return request(
        url,
        (body) =>
          Boolean(
            body &&
            Array.isArray(body.items) &&
            Number.isSafeInteger(body.total) &&
            body.total >= body.items.length &&
            body.items.length <= 500 &&
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
    /** @param {ReportQuery} query @param {{signal?: AbortSignal}} [options] @returns {Promise<Stats>} */
    getStats(query, options) {
      return request(filteredUrl('stats', query), isStats, options);
    },
    /** @param {ReportQuery} query @returns {string} */
    getCsvUrl(query) {
      return filteredUrl('reports.csv', query).href;
    },
  };
}

/** @typedef {{total: number, by_category: Object<string, number>, by_status: Object<string, number>, by_resolution: Object<string, number>}} Stats */
/** @param {unknown} body @returns {body is Stats} */
function isStats(body) {
  if (!body || !Number.isSafeInteger(body.total) || body.total < 0)
    return false;
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
