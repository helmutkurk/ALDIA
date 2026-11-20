import { afterEach, expect, it, vi } from 'vitest';
import { createApiClient } from '../src/api.js';
import { createDashboard } from '../src/dashboard.js';
import { recentDates } from '../src/dashboard-recent.js';
import snapshot from './fixtures/stats-api-snapshot.json';
import recentSnapshot from './fixtures/stats-recent-snapshot.json';

// Aggregate-only snapshots from the running demo API on 2026-11-20. That process
// still served percentages. Normalize this one field in the fixture to the binding
// ratio contract; production validation deliberately rejects the stale response.
const contractShape = (value) => ({
  ...value,
  tasa_resolucion:
    value.tasa_resolucion > 1
      ? value.tasa_resolucion / 100
      : value.tasa_resolucion,
});
const json = (body) => new Response(JSON.stringify(body), { status: 200 });
const flush = async () => {
  for (let i = 0; i < 20; i++) await Promise.resolve();
};
let page;
afterEach(() => {
  page?.destroy();
  document.body.replaceChildren();
  vi.useRealTimers();
});

it('accepts a 0–1 resolution ratio and rejects the former percentage representation', async () => {
  const fetchImpl = vi.fn(async () => json(contractShape(snapshot)));
  const api = createApiClient({ fetchImpl });
  expect(
    (await api.getStats({ include_old: true })).tasa_resolucion,
  ).toBeCloseTo(26 / 61);
  for (const value of [0, 1, null]) {
    fetchImpl.mockResolvedValueOnce(
      json({ ...snapshot, tasa_resolucion: value }),
    );
    expect((await api.getStats({})).tasa_resolucion).toBe(value);
  }
  fetchImpl.mockResolvedValueOnce(
    json({ ...snapshot, tasa_resolucion: 42.622950819672134 }),
  );
  await expect(api.getStats({})).rejects.toMatchObject({
    error: { code: 'invalid_response' },
  });
});

it('renders real-shaped counters, cumulative lines, seven-day activity and category repairs through the API validator', async () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-11-20T12:00:00Z'));
  const fetchImpl = vi.fn(async (url) =>
    json(
      contractShape(
        new URL(url).searchParams.has('created_from')
          ? recentSnapshot
          : snapshot,
      ),
    ),
  );
  const root = document.createElement('section');
  document.body.append(root);
  page = createDashboard(root, {
    api: createApiClient({ fetchImpl }),
    filters: { bbox: [-91, 14, -90, 15] },
  });
  await flush();
  expect(root.querySelector('[role="alert"]')).toBeNull();
  expect(root.querySelectorAll('.weekly-line')).toHaveLength(2);
  expect(
    [...root.querySelectorAll('.chart-total dd')].map(
      (node) => node.textContent,
    ),
  ).toEqual(['66', '26']);
  const metrics = root.querySelector(
    '.metric-cards:not(.kpi-strip)',
  ).textContent;
  expect(metrics).toContain('42.6 %');
  expect(metrics).toContain('SLA cumplido76.9 %');
  expect(metrics).toContain('Vencidos12');
  expect(root.querySelector('.last-week h2').textContent).toBe(
    'Últimos 7 días',
  );
  expect(
    [...root.querySelectorAll('.spark-value')].map((node) => node.textContent),
  ).toEqual(['22', '19']);
  const [all, recent] = fetchImpl.mock.calls.map(([url]) => new URL(url));
  expect(all.searchParams.get('include_old')).toBe('true');
  expect(recent.searchParams.get('created_from')).toBe('2026-11-14');
  expect(recent.searchParams.get('created_to')).toBe('2026-11-20');
  expect(recent.searchParams.get('bbox')).toBe('-91,14,-90,15');
  expect(root.querySelectorAll('.top-categories li')).toHaveLength(5);
  expect(root.querySelector('.category-repair').textContent).toContain('57 h');
  for (const name of ['category-repair', 'category-frequency']) {
    const chart = root.querySelector(`.${name}`);
    expect(
      chart.querySelector('.chart-note').textContent.length,
    ).toBeGreaterThan(30);
    const details = chart.querySelector('details');
    expect(details.querySelector('summary').textContent).toBe('Ver tabla');
    details.querySelector('summary').click();
    expect(details.open).toBe(true);
  }
  expect(root.querySelector('.csv-link').textContent).toBe('Descargar CSV');
  expect(document.activeElement).toBe(root.querySelector('h1[tabindex="-1"]'));
  expect(root.querySelector('.dash-body > .weekly-chart')).toBe(
    root.querySelector('.dashboard-total').nextElementSibling,
  );
  expect(fetchImpl).toHaveBeenCalledTimes(2); // Cross-tab queries remain deferred.
});

it('uses Guatemala calendar boundaries across a month and keeps the recent failure local', async () => {
  expect(recentDates(new Date('2026-12-01T01:00:00Z'))).toEqual({
    created_from: '2026-11-24',
    created_to: '2026-11-30',
  });
  const root = document.createElement('section');
  const api = {
    getStats: vi
      .fn()
      .mockResolvedValueOnce(contractShape(snapshot))
      .mockRejectedValueOnce(new Error('offline')),
    getCsvUrl: () => '/api/reports.csv',
  };
  page = createDashboard(root, { api, filters: {} });
  await flush();
  expect(root.querySelectorAll('.weekly-line')).toHaveLength(2);
  expect(root.querySelector('.last-week').textContent).toContain(
    'No se pudo cargar la actividad reciente',
  );
  api.getStats.mockResolvedValueOnce(contractShape(recentSnapshot));
  root.querySelector('.last-week button').click();
  await flush();
  expect(root.querySelectorAll('.spark-value')).toHaveLength(2);
});
