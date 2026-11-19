import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, createApiClient, safePhotoUrl } from '../src/api.js';
import { report } from './fixtures.js';

const response = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

afterEach(() => vi.useRealTimers());

describe('reports API client', () => {
  it('sends bbox in lon/lat order, filters and the 25-report page size', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(response({ items: [report()], total: 700 }));
    const api = createApiClient({ baseUrl: '/api/', fetchImpl });
    const result = await api.getReports({
      bbox: [-90.6, 14.5, -90.4, 14.7],
      category: 'pothole',
      status: 'verified',
    });
    const url = new URL(fetchImpl.mock.calls[0][0]);
    expect(url.pathname).toBe('/api/reports');
    expect(Object.fromEntries(url.searchParams)).toEqual({
      bbox: '-90.6,14.5,-90.4,14.7',
      category: 'pothole',
      status: 'verified',
      limit: '25',
    });
    expect(result.total).toBe(700);
    expect(result.items).toHaveLength(1);
  });

  it('supports an absolute API base and omits empty filters', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(response({ items: [], total: 0 }));
    await createApiClient({
      baseUrl: 'https://api.example.test/api',
      fetchImpl,
    }).getReports({ bbox: [-91, 14, -90, 15] });
    const url = new URL(fetchImpl.mock.calls[0][0]);
    expect(url.origin).toBe('https://api.example.test');
    expect(url.searchParams.has('category')).toBe(false);
    expect(url.searchParams.has('status')).toBe(false);
  });

  it('preserves the contract error object and HTTP status', async () => {
    const error = { code: 'invalid_bbox', message: 'Zona no válida' };
    const api = createApiClient({
      fetchImpl: vi.fn().mockResolvedValue(response({ error }, 422)),
    });
    await expect(
      api.getReports({ bbox: [-91, 14, -90, 15] }),
    ).rejects.toMatchObject({ error, status: 422 });
  });

  it('maps non-JSON HTTP failures and network failures to contract-shaped errors', async () => {
    const options = { bbox: [-91, 14, -90, 15] };
    const badGateway = createApiClient({
      fetchImpl: vi
        .fn()
        .mockResolvedValue(
          new Response('<h1>Bad gateway</h1>', { status: 502 }),
        ),
    });
    await expect(badGateway.getReports(options)).rejects.toMatchObject({
      error: { code: 'http_error' },
      status: 502,
    });
    const offline = createApiClient({
      fetchImpl: vi.fn().mockRejectedValue(new TypeError('offline')),
    });
    await expect(offline.getReports(options)).rejects.toMatchObject({
      error: { code: 'network_error' },
      status: 0,
    });
  });

  it.each([
    {},
    { items: {}, total: 0 },
    { items: [], total: -1 },
    { items: [report({ latitude: NaN })], total: 1 },
    { items: [report({ status: 'other' })], total: 1 },
    { items: [report({ category: 'unknown' })], total: 1 },
    { items: [report({ verification: { mode: 'stub' } })], total: 1 },
    { items: [report({ captured_at: 'bad date' })], total: 1 },
    { items: [report({ id: '../bad' })], total: 1 },
  ])('rejects malformed success payloads: %j', async (body) => {
    const api = createApiClient({
      fetchImpl: vi.fn().mockResolvedValue(response(body)),
    });
    await expect(
      api.getReports({ bbox: [-91, 14, -90, 15] }),
    ).rejects.toMatchObject({ error: { code: 'invalid_response' } });
  });

  it('accepts pending reports without verification', async () => {
    const pending = report({ status: 'pending', verification: null });
    const api = createApiClient({
      fetchImpl: vi
        .fn()
        .mockResolvedValue(response({ items: [pending], total: 1 })),
    });
    expect((await api.getReports({ bbox: [-91, 14, -90, 15] })).items).toEqual([
      pending,
    ]);
  });

  it('propagates caller cancellation instead of showing a network error', async () => {
    const controller = new AbortController();
    const api = createApiClient({
      fetchImpl: vi.fn(
        (_url, { signal }) =>
          new Promise((_resolve, reject) =>
            signal.addEventListener('abort', () => reject(signal.reason)),
          ),
      ),
    });
    const request = api.getReports(
      { bbox: [-91, 14, -90, 15] },
      { signal: controller.signal },
    );
    controller.abort();
    await expect(request).rejects.toMatchObject({ name: 'AbortError' });
  });

  it('times out a stalled request with a contract-shaped error', async () => {
    vi.useFakeTimers();
    const api = createApiClient({
      timeoutMs: 50,
      fetchImpl: vi.fn(
        (_url, { signal }) =>
          new Promise((_resolve, reject) =>
            signal.addEventListener('abort', () => reject(signal.reason)),
          ),
      ),
    });
    const assertion = expect(
      api.getReports({ bbox: [-91, 14, -90, 15] }),
    ).rejects.toBeInstanceOf(ApiError);
    await vi.advanceTimersByTimeAsync(50);
    await assertion;
  });
});

describe('photo URLs', () => {
  it('only permits photo endpoints on the configured API origin and prefix', () => {
    expect(safePhotoUrl(report().photo_url)).toContain(report().photo_url);
    expect(safePhotoUrl('javascript:alert(1)')).toBeNull();
    expect(safePhotoUrl('https://tracker.example.test/photo')).toBeNull();
    expect(safePhotoUrl('/api/reports/not-a-uuid/photo')).toBeNull();
    expect(safePhotoUrl('/other/photo')).toBeNull();
    expect(
      safePhotoUrl(
        `https://api.example.test${report().photo_url}`,
        'https://api.example.test/api',
      ),
    ).toBe(`https://api.example.test${report().photo_url}`);
  });
});

describe('v0.1 report, statistics and export endpoints', () => {
  const query = {
    bbox: [-91, 14, -90, 15],
    category: 'pothole',
    status: 'verified',
    resolution: 'fixed',
  };
  const stats = {
    total: 3,
    by_category: { pothole: 3 },
    by_status: { verified: 3 },
    by_resolution: { fixed: 3 },
  };
  it('uses identical filters for reports, stats and CSV, without list limits on stats/export', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(response({ items: [], total: 0 }))
      .mockResolvedValueOnce(response(stats));
    const api = createApiClient({
      baseUrl: 'https://api.example.test/v1/api',
      fetchImpl,
    });
    await api.getReports(query);
    expect(await api.getStats(query)).toEqual(stats);
    const list = new URL(fetchImpl.mock.calls[0][0]);
    const summary = new URL(fetchImpl.mock.calls[1][0]);
    const csv = new URL(api.getCsvUrl(query));
    expect(list.searchParams.get('resolution')).toBe('fixed');
    expect(summary.pathname).toBe('/v1/api/stats');
    expect(csv.pathname).toBe('/v1/api/reports.csv');
    list.searchParams.delete('limit');
    expect(list.search).toBe(summary.search);
    expect(summary.search).toBe(csv.search);
  });
  it('validates detail UUIDs before fetching and validates returned report identity and resolution', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(response(report()));
    const api = createApiClient({ fetchImpl });
    expect(() => api.getReport('../reports.csv')).toThrow(TypeError);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(await api.getReport(report().id)).toEqual(report());
    expect(new URL(fetchImpl.mock.calls[0][0]).pathname).toBe(
      `/api/reports/${report().id}`,
    );
    fetchImpl.mockResolvedValue(response(report({ resolution: 'unknown' })));
    await expect(api.getReport(report().id)).rejects.toMatchObject({
      error: { code: 'invalid_response' },
    });
    fetchImpl.mockResolvedValue(
      response(report({ id: '22345678-1234-4234-8234-123456789abc' })),
    );
    await expect(api.getReport(report().id)).rejects.toMatchObject({
      error: { code: 'invalid_response' },
    });
  });
  it.each([
    { ...stats, total: -1 },
    { ...stats, by_category: { unknown: 3 } },
    { ...stats, by_status: { verified: '3' } },
    { ...stats, by_resolution: { fixed: 2 } },
    { ...stats, by_resolution: null },
  ])('rejects malformed statistics %j', async (body) => {
    const api = createApiClient({
      fetchImpl: vi.fn().mockResolvedValue(response(body)),
    });
    await expect(api.getStats({})).rejects.toMatchObject({
      error: { code: 'invalid_response' },
    });
  });
  it('accepts empty stats and propagates missing-report contract errors', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(
        response({
          total: 0,
          by_category: {},
          by_status: {},
          by_resolution: {},
        }),
      )
      .mockResolvedValueOnce(
        response({ error: { code: 'not_found', message: 'Not found' } }, 404),
      );
    const api = createApiClient({ fetchImpl });
    expect((await api.getStats({})).total).toBe(0);
    await expect(api.getReport(report().id)).rejects.toMatchObject({
      status: 404,
      error: { code: 'not_found' },
    });
  });
});
