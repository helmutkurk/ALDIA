import { afterEach, expect, it, vi } from 'vitest';
import { createApiClient } from '../src/api.js';
import { createDashboard } from '../src/dashboard.js';
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

it('renders the real-shaped snapshot through the API validator with the mockup cards', async () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-11-20T12:00:00Z'));
  const fetchImpl = vi.fn(async (url) =>
    json(
      contractShape(
        new URL(url).searchParams.get('created_to') === '2026-11-20'
          ? snapshot
          : recentSnapshot,
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
  const [current, previous] = fetchImpl.mock.calls.map(([url]) => new URL(url));
  expect(current.searchParams.get('created_from')).toBe('2026-10-22');
  expect(previous.searchParams.get('created_to')).toBe('2026-10-21');
  expect(current.searchParams.get('bbox')).toBe('-91,14,-90,15');
  const values = [...root.querySelectorAll('.stat-kpi-value')].map(
    (node) => node.textContent,
  );
  expect(values[0]).toBe('66');
  expect(values[1]).toBe('42.6 %');
  expect(root.querySelectorAll('.stat-trend polyline')).toHaveLength(2);
  expect(root.querySelector('.stat-times').textContent).toContain('76.9 %');
  expect(root.querySelector('.stat-times').textContent).toContain('12');
  expect(root.querySelectorAll('.stat-frequency .stat-row')).toHaveLength(6);
  expect(
    root.querySelector('.stat-repair .stat-row-value').textContent,
  ).toMatch(/ d$/);
  expect(root.querySelector('.csv-link').textContent).toBe('Descargar CSV');
  expect(document.activeElement).toBe(root.querySelector('h1[tabindex="-1"]'));
  expect(fetchImpl).toHaveBeenCalledTimes(2); // Cross-tab queries remain deferred.
});
