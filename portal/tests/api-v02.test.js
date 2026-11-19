import { afterEach, expect, it, vi } from 'vitest';
import { createApiClient } from '../src/api.js';
import { createStaffSession } from '../src/staff.js';
import { createDashboard } from '../src/dashboard.js';
import { municipalReport } from './fixtures.js';

const json = (value, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
const stats = () => ({
  total: 0,
  by_category: {},
  by_status: {},
  by_resolution: {},
  recibidos: 0,
  rechazados_verificador: 0,
  abiertos: 0,
  resueltos: 0,
  cerrados_sin_solucion: 0,
  tasa_resolucion: null,
  resolucion_horas: { median: null, p90: null, mean: null, n: 0 },
  primera_respuesta_horas: { median: null, p90: null, n: 0 },
  antiguedad_abiertos: { '0-2': 0, '3-7': 0, '8-30': 0, '>30': 0 },
  sla_cumplido: null,
  vencidos: 0,
  by_state: {},
  by_state_group: {},
  weekly: [],
});
let staff, page;
afterEach(() => {
  page?.destroy();
  staff?.destroy();
  page = staff = null;
  document.body.replaceChildren();
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it('validates all additive statistics without interpreting missing or null samples as zero', async () => {
  vi.useFakeTimers();
  const fetchImpl = vi.fn(async () => json(stats()));
  const api = createApiClient({ fetchImpl });
  expect((await api.getStats({})).tasa_resolucion).toBeNull();
  for (const patch of [
    { recibidos: -1 },
    { tasa_resolucion: '50%' },
    { resolucion_horas: { median: -1, p90: 0, mean: 0, n: 1 } },
    { primera_respuesta_horas: null },
    { by_state_group: { bad: 1 } },
    { weekly: [{ week: '<svg>', recibidos: 2, resueltos: 1 }] },
  ]) {
    fetchImpl.mockImplementationOnce(async () =>
      json({ ...stats(), ...patch }),
    );
    await expect(api.getStats({})).rejects.toMatchObject({
      error: { code: 'invalid_response' },
    });
  }
  expect(vi.getTimerCount()).toBe(0);
});

it('rejects unknown states, mismatched groups, malformed events and invalid assignment types', async () => {
  const fetchImpl = vi.fn();
  const api = createApiClient({ fetchImpl });
  for (const patch of [
    { state: 'other' },
    { state_group: 'resolved' },
    { events: [{ at: 'bad' }] },
    { assignee: {} },
    { verified_at: 'bad' },
  ]) {
    fetchImpl.mockResolvedValueOnce(json(municipalReport(patch)));
    await expect(api.getReport(municipalReport().id)).rejects.toMatchObject({
      error: { code: 'invalid_response' },
    });
  }
});

it('accepts filtered cluster payloads and rejects malformed pins before rendering', async () => {
  const fetchImpl = vi.fn(async () => json({ clusters: [], total: 0 }));
  const api = createApiClient({ fetchImpl });
  await api.getClusters({
    bbox: [-91, 14, -90, 15],
    zoom: 19,
    state_group: 'open',
    assignee: 'A & B',
    include_old: 'true',
  });
  const url = new URL(fetchImpl.mock.calls[0][0]);
  expect(Object.fromEntries(url.searchParams)).toEqual({
    bbox: '-91,14,-90,15',
    zoom: '19',
    state_group: 'open',
    assignee: 'A & B',
    include_old: 'true',
  });
  for (const cluster of [
    { lat: 91, lon: 0, count: 2 },
    { lat: 14, lon: 0, count: 0 },
    { lat: 14, lon: 0, count: 1, ids: ['../'] },
    { lat: '14', lon: 0, count: 1 },
  ]) {
    fetchImpl.mockResolvedValueOnce(json({ clusters: [cluster], total: 1 }));
    await expect(
      api.getClusters({ bbox: [-91, 14, -90, 15], zoom: 19 }),
    ).rejects.toMatchObject({ error: { code: 'invalid_response' } });
  }
});

it('preserves staff headers and delimiter filters for CSV body downloads and accepts empty assignment success', async () => {
  vi.useFakeTimers();
  staff = createStaffSession();
  staff.setToken('test-staff-session-token-0000000000');
  const fetchImpl = vi.fn(async (url) =>
    url.endsWith('/assign')
      ? new Response(null, { status: 204 })
      : new Response('\uFEFFid;category\r\n', {
          headers: { 'Content-Type': 'text/csv' },
        }),
  );
  const api = createApiClient({ staff, fetchImpl });
  const blob = await api.getCsvBlob({
    state: 'nuevo',
    delimiter: 'semicolon',
    created_from: '2026-11-01',
  });
  expect(await blob.text()).toContain('id;category');
  const [url, options] = fetchImpl.mock.calls[0];
  expect(new URL(url).searchParams.get('delimiter')).toBe('semicolon');
  expect(options.headers['X-Staff-Token']).toBe(staff.getToken());
  expect(options.redirect).toBe('error');
  expect(url).not.toContain(staff.getToken());
  await expect(api.assign(municipalReport().id, null)).resolves.toBeNull();
  expect(vi.getTimerCount()).toBe(0);
});

it('dashboard downloads CSV through authenticated fetch and releases its blob URL on teardown', async () => {
  vi.useFakeTimers();
  const create = vi.fn(() => 'blob:synthetic-csv');
  const revoke = vi.fn();
  vi.stubGlobal(
    'URL',
    class extends URL {
      static createObjectURL = create;
      static revokeObjectURL = revoke;
    },
  );
  const click = vi
    .spyOn(window.HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
  const root = document.createElement('section');
  document.body.append(root);
  const fetchImpl = vi.fn(async (url) =>
    new URL(url).pathname.endsWith('/reports.csv')
      ? new Response('id,category')
      : json(stats()),
  );
  staff = createStaffSession();
  staff.setToken('synthetic-staff-token-for-csv-tests');
  page = createDashboard(root, {
    api: createApiClient({ staff, fetchImpl }),
    filters: { category: 'pothole', include_old: 'true' },
  });
  await vi.advanceTimersByTimeAsync(0);
  root
    .querySelector('.csv-link')
    .dispatchEvent(
      new window.MouseEvent('click', { bubbles: true, cancelable: true }),
    );
  await vi.advanceTimersByTimeAsync(0);
  expect(create).toHaveBeenCalledOnce();
  expect(click).toHaveBeenCalledOnce();
  const [, options] = fetchImpl.mock.calls.find(([url]) =>
    new URL(url).pathname.endsWith('/reports.csv'),
  );
  expect(options.headers['X-Staff-Token']).toBe(staff.getToken());
  page.destroy();
  page = null;
  expect(revoke).toHaveBeenCalledWith('blob:synthetic-csv');
});
