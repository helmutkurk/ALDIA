import { UUID } from './api-validation.js';

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '/api';

/** @param {string} baseUrl */
export function apiBase(baseUrl) {
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
