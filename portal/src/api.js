import { FILTER_KEYS } from './filters.js';
import { createRequest } from './api-request.js';
export { ApiError } from './api-request.js';

/** Public typedef paths are retained for existing consumers. */
/** @typedef {import('./api-types.js').ErrorDetail} ErrorDetail */
/** @typedef {import('./api-types.js').VerificationCheck} VerificationCheck */
/** @typedef {import('./api-types.js').Verification} Verification */
/** @typedef {import('./api-types.js').Report} Report */
/** @typedef {import('./api-types.js').ReportPage} ReportPage */
/** @typedef {import('./api-types.js').Bbox} Bbox */
/** @typedef {import('./api-types.js').ReportQuery} ReportQuery */
/** @typedef {import('./api-types.js').Stats} Stats */

import { API_BASE_URL, apiBase, safePhotoUrl } from './api-urls.js';
export { safePhotoUrl } from './api-urls.js';
export { uuidPattern } from './api-validation.js';
import {
  uuidPattern,
  isReport,
  isStats,
  isUserEnvelope,
  isReportPage,
  isQueuePage,
  isClusterPage,
} from './api-validation.js';

/**
 * @param {{baseUrl?: string, fetchImpl?: typeof fetch, timeoutMs?: number, staff?: import('./api-types.js').StaffIdentity|null}} [options]
 */
export function createApiClient({
  baseUrl = API_BASE_URL,
  fetchImpl = globalThis.fetch,
  timeoutMs = 15000,
  staff = null,
} = {}) {
  const base = apiBase(baseUrl);
  const request = createRequest({ fetchImpl, timeoutMs, staff });
  /** @param {string} path @param {ReportQuery} query */
  function filteredUrl(path, query) {
    const url = new URL(path, base);
    if (query.bbox) url.searchParams.set('bbox', query.bbox.join(','));
    for (const name of FILTER_KEYS.filter((key) => key !== 'bbox')) {
      if (query[name]) url.searchParams.set(name, query[name]);
    }
    return url;
  }
  return {
    /** @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<import('./api-types.js').AuthConfig>} */
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
    /** @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<import('./api-types.js').UserEnvelope>} */
    getMe(options) {
      return request(new URL('auth/me', base), isUserEnvelope, options);
    },
    /** @param {string} username @param {string} password @returns {Promise<import('./api-types.js').UserEnvelope>} */
    login(username, password) {
      return request(new URL('auth/login', base), isUserEnvelope, {
        method: 'POST',
        body: { username, password },
      });
    },
    /** @returns {Promise<null>} */
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
      return request(url, isReportPage, options);
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
    /** @param {ReportQuery & {zoom: number}} query @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<import('./api-types.js').ClusterPage>} */
    getClusters(query, options) {
      const url = filteredUrl('reports/clusters', query);
      url.searchParams.set('zoom', String(query.zoom));
      return request(url, isClusterPage, options);
    },
    /** @param {string} id @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<Report[]>} */
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
    /** @param {'review'|'rejected'} tab @param {ReportQuery} [query] @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<ReportPage>} */
    getQueue(tab, query = {}, options) {
      const url = new URL('queue', base);
      url.searchParams.set('tab', tab);
      url.searchParams.set('limit', '25');
      if (query.offset) url.searchParams.set('offset', String(query.offset));
      return request(url, isQueuePage, options);
    },
    /** @param {string} id @param {import('./api-types.js').TransitionRequest} body @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<Report>} */
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
     * @param {string} id @param {string|null} assignee @param {import('./api-types.js').ReadOptions} [options]
     * @returns {Promise<Record<string, unknown>|unknown[]|null>} */
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
    /** @param {string} value @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<Blob>} */
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
     * @param {ReportQuery} query @param {import('./api-types.js').ReadOptions} [options] @returns {Promise<Blob>} */
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
