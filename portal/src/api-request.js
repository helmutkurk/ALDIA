import { t } from './i18n.js';

/** @typedef {import('./api-types.js').ErrorDetail} ErrorDetail */

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

/** Own HTTP policy independently of endpoint URLs and payload validators.
 * @param {{fetchImpl: typeof fetch, timeoutMs: number, staff: import('./api-types.js').StaffIdentity|null}} options
 */
export function createRequest({ fetchImpl, timeoutMs, staff }) {
  const csrfToken = () => {
    const value = globalThis.document?.cookie
      .split(';')
      .map((cookie) => cookie.trim())
      .find((cookie) => cookie.startsWith('aldia_csrf='));
    return value ? decodeURIComponent(value.slice('aldia_csrf='.length)) : '';
  };
  /** Shared deadlines, cancellation and contract-shaped errors for every endpoint.
   * @template T
   * @param {URL} url @param {(body: unknown) => body is T} validate
   * @param {import('./api-types.js').RequestOptions} [options]
   * @returns {Promise<T>}
   */
  return async function request(
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
  };
}
