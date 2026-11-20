import { FILTER_KEYS } from './filters.js';
import { t } from './i18n.js';

/** @typedef {{code: string, message: string}} ErrorDetail */
/** @typedef {{name: string, passed: boolean, detail: string}} VerificationCheck */
/** @typedef {{passed: boolean, mode: 'stub'|'heuristic'|'model', checks: VerificationCheck[]}} Verification */
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

import { API_BASE_URL, apiBase, safePhotoUrl } from './api-urls.js';
export { safePhotoUrl } from './api-urls.js';
export { uuidPattern } from './api-validation.js';
import { uuidPattern, isReport, isStats } from './api-validation.js';

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

/** @param {unknown} value @returns {value is ErrorDetail} */
function isErrorDetail(value) {
  return (
    value !== null &&
    typeof value === 'object' &&
    typeof value.code === 'string' &&
    typeof value.message === 'string'
  );
}

/**
 * @param {{baseUrl?: string, fetchImpl?: typeof fetch, timeoutMs?: number, staff?: object|null}} [options]
 */
export function createApiClient({
  baseUrl = API_BASE_URL,
  fetchImpl = globalThis.fetch,
  timeoutMs = 15000,
  staff = null,
} = {}) {
  const base = apiBase(baseUrl);
  const isUserEnvelope = (body) =>
    body &&
    typeof body.user?.username === 'string' &&
    ['operator', 'supervisor', 'admin'].includes(body.user.role);
  const csrfToken = () => {
    const value = globalThis.document?.cookie
      .split(';')
      .map((cookie) => cookie.trim())
      .find((cookie) => cookie.startsWith('aldia_csrf='));
    return value ? decodeURIComponent(value.slice('aldia_csrf='.length)) : '';
  };
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
    const identity = staff?.getUser?.() ?? staff?.getToken?.();
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
      const csrf =
        !['GET', 'HEAD'].includes(method) &&
        !url.pathname.endsWith('/auth/login')
          ? csrfToken()
          : '';
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
          ...(csrf ? { 'X-CSRF-Token': csrf } : {}),
        },
        ...(payload ? { body: JSON.stringify(payload) } : {}),
        cache: 'no-store',
        credentials: 'include',
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
      if (error instanceof ApiError) {
        if (
          error.status === 401 &&
          identity &&
          !url.pathname.endsWith('/auth/login') &&
          identity === (staff?.getUser?.() ?? staff?.getToken?.())
        )
          staff?.clear?.(error);
        // Clearing identity synchronously cancels the old private view. Preserve
        // this HTTP error even when that subscriber aborts the request signal.
        throw error;
      }
      throw new ApiError({ code: 'network_error', message: t.networkError });
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
    }
  }
  return {
    getAuthConfig(options) {
      return request(
        new URL('auth/config', base),
        (body) =>
          body &&
          typeof body.enabled === 'boolean' &&
          typeof body.dev_tokens === 'boolean',
        options,
      );
    },
    getMe(options) {
      return request(new URL('auth/me', base), isUserEnvelope, options);
    },
    login(username, password) {
      return request(new URL('auth/login', base), isUserEnvelope, {
        method: 'POST',
        body: { username, password },
      });
    },
    logout() {
      return request(new URL('auth/logout', base), (body) => body === null, {
        method: 'POST',
      });
    },
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
    hasStaff: () => Boolean(staff?.getRole?.() || staff?.getToken()),
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
