import { afterEach, expect, it, vi } from 'vitest';
import { ApiError, createApiClient } from '../src/api.js';
import { report } from './fixtures.js';

afterEach(() => vi.useRealTimers());

it('does not fetch or start a deadline for an already-cancelled request', async () => {
  vi.useFakeTimers();
  const controller = new AbortController();
  controller.abort();
  const fetchImpl = vi.fn();
  const api = createApiClient({ fetchImpl });
  await expect(api.getReports({}, { signal: controller.signal })).rejects.toBe(
    controller.signal.reason,
  );
  expect(fetchImpl).not.toHaveBeenCalled();
  expect(vi.getTimerCount()).toBe(0);
});

it.each([
  [200, 'invalid_response'],
  [502, 'http_error'],
])(
  'keeps error policy for a non-JSON response with status %i',
  async (status, code) => {
    const api = createApiClient({
      fetchImpl: async () => new Response('not JSON', { status }),
    });
    await expect(api.getReports({})).rejects.toMatchObject({
      status,
      error: { code },
    });
  },
);

it('applies its deadline while decoding the response body and keeps the exported error class', async () => {
  vi.useFakeTimers();
  const api = createApiClient({
    timeoutMs: 50,
    fetchImpl: async (_url, { signal }) => ({
      ok: true,
      status: 200,
      json: () =>
        new Promise((_resolve, reject) => {
          signal.addEventListener('abort', () => reject(signal.reason), {
            once: true,
          });
        }),
    }),
  });
  const result = api.getReports({});
  const assertion = expect(result).rejects.toMatchObject({
    name: 'ApiError',
    error: { code: 'timeout' },
  });
  await vi.advanceTimersByTimeAsync(50);
  await assertion;
  await expect(result).rejects.toBeInstanceOf(ApiError);
  expect(vi.getTimerCount()).toBe(0);
});

it('retains the distinct duplicate-ID policies of report and queue pages', async () => {
  const page = { items: [report(), report()], total: 2 };
  const api = createApiClient({
    fetchImpl: async () => new Response(JSON.stringify(page)),
  });
  await expect(api.getReports({})).rejects.toMatchObject({
    error: { code: 'invalid_response' },
  });
  await expect(api.getQueue('review')).resolves.toEqual(page);
});
