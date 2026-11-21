import { expect, it, vi } from 'vitest';
import { loadWorkspace } from '../src/workspace-load.js';
import { createStore } from '../src/state.js';
import { report } from './fixtures.js';
import { ui } from '../src/i18n.js';

const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};
function setup(overrides = {}) {
  return {
    api: {
      getReports: vi.fn().mockResolvedValue({ items: [], total: 0 }),
      ...overrides,
    },
    map: { getZoom: () => 13, renderClusters: vi.fn() },
    store: createStore(),
    side: document.createElement('section'),
    filters: { category: 'pothole' },
    signal: new AbortController().signal,
    isCurrent: () => true,
    onLoaded: vi.fn(),
    reload: vi.fn(),
  };
}

it('starts list and clusters together and preserves the list after an early cluster failure', async () => {
  let respond;
  const options = setup({
    getReports: vi.fn(
      () =>
        new Promise((resolve) => {
          respond = resolve;
        }),
    ),
    getClusters: vi.fn().mockRejectedValue(new Error('offline')),
  });
  const pending = loadWorkspace(options);
  expect(options.api.getReports).toHaveBeenCalledOnce();
  expect(options.api.getClusters).toHaveBeenCalledOnce();
  await flush();
  respond({ items: [report()], total: 1 });
  await pending;
  expect(options.store.getState()).toMatchObject({
    phase: 'success',
    reports: [report()],
    total: 1,
  });
  expect(options.side.textContent).toBe(ui.clusterError);
  expect(options.map.renderClusters).toHaveBeenCalledWith([]);
});

it('reuses cached reports while keeping singleton hydration at six concurrent reads', async () => {
  const cached = report();
  const ids = Array.from(
    { length: 9 },
    (_, n) => `${n + 1}2345678-1234-4234-8234-123456789abc`,
  );
  const clusters = [...ids, cached.id.toUpperCase()].map((id) => ({
    lat: 14,
    lon: -90,
    count: 1,
    ids: [id],
  }));
  const requests = [];
  const options = setup({
    getReports: vi.fn().mockResolvedValue({ items: [cached], total: 1 }),
    getClusters: vi
      .fn()
      .mockResolvedValue({ clusters, total: clusters.length }),
    getReport: vi.fn(
      (id) =>
        new Promise((resolve) => {
          requests.push({ id, resolve });
        }),
    ),
  });
  const pending = loadWorkspace(options);
  await flush();
  expect(requests).toHaveLength(6);
  expect(options.map.renderClusters).not.toHaveBeenCalled();
  requests[0].resolve(report({ id: requests[0].id }));
  await flush();
  expect(requests).toHaveLength(7);
  requests[1].resolve(report({ id: requests[1].id }));
  await flush();
  expect(requests).toHaveLength(8);
  for (const request of requests) request.resolve(report({ id: request.id }));
  await pending;
  expect(options.api.getReport.mock.calls.map(([id]) => id)).not.toContain(
    cached.id,
  );
  expect(options.map.renderClusters).toHaveBeenCalledWith(
    clusters,
    expect.arrayContaining([cached]),
  );
  expect(options.map.renderClusters.mock.calls[0][1]).toHaveLength(
    clusters.length,
  );
});

it('suppresses hydrated pins from an obsolete generation', async () => {
  let respond,
    current = true;
  const options = setup({
    getClusters: vi.fn().mockResolvedValue({
      clusters: [{ count: 1, ids: [report().id] }],
      total: 1,
    }),
    getReport: vi.fn(
      () =>
        new Promise((resolve) => {
          respond = resolve;
        }),
    ),
  });
  options.isCurrent = () => current;
  const pending = loadWorkspace(options);
  await flush();
  current = false;
  respond(report());
  await pending;
  expect(options.map.renderClusters).not.toHaveBeenCalled();
  expect(options.side.childElementCount).toBe(0);
});

it('corrects an out-of-range page before publishing reports or clusters', async () => {
  const options = setup({
    getClusters: vi.fn().mockResolvedValue({ clusters: [], total: 0 }),
  });
  options.store.setOffset(50);
  options.api.getReports.mockResolvedValue({ items: [], total: 26 });
  await loadWorkspace(options);
  expect(options.store.getState().offset).toBe(25);
  expect(options.reload).toHaveBeenCalledOnce();
  expect(options.onLoaded).not.toHaveBeenCalled();
  expect(options.map.renderClusters).not.toHaveBeenCalled();
});
