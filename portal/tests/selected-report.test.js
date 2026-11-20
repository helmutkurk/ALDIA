import { afterEach, expect, it, vi } from 'vitest';
import { createSelection } from '../src/selected-report.js';
import { municipalReport } from './fixtures.js';
import { ui } from '../src/i18n.js';
let selection;
afterEach(() => {
  selection?.clear();
  document.body.replaceChildren();
});
it('recovers from detail errors and restores keyboard focus when closed', async () => {
  const row = document.createElement('button');
  const side = document.createElement('section');
  document.body.append(row, side);
  const api = {
    getReport: vi
      .fn()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce(municipalReport()),
  };
  selection = createSelection(side, {
    api,
    staff: null,
    getScope: () => ({}),
    onSaved: vi.fn(),
  });
  row.focus();
  await selection.showReport(municipalReport().id);
  expect(side.querySelector('[role="alert"]')).not.toBeNull();
  side.querySelector('.retry-button').click();
  for (let i = 0; i < 5; i++) await Promise.resolve();
  expect(side.querySelector('h2').textContent).toBe('Bache');
  expect(document.activeElement.tagName).toBe('H2');
  side.querySelector('button').click();
  expect(side.childElementCount).toBe(0);
  expect(document.activeElement).toBe(row);
});

const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};
function clusterSelection() {
  const side = document.createElement('section');
  document.body.append(side);
  const requests = [];
  const api = {
    getReport: vi.fn(
      (id, { signal }) =>
        new Promise((resolve, reject) => {
          requests.push({ id, signal, resolve, reject });
        }),
    ),
  };
  selection = createSelection(side, {
    api,
    staff: null,
    getScope: () => ({ category: 'pothole' }),
    onSaved: vi.fn(),
  });
  const ids = [1, 2, 3].map((n) => `${n}2345678-1234-4234-8234-123456789abc`);
  const pending = selection.showCluster({ count: 4, ids });
  return { side, api, requests, ids, pending };
}

it('starts cluster reads together and progressively renders in server order', async () => {
  const { side, api, requests, ids, pending } = clusterSelection();
  expect(api.getReport.mock.calls.map(([id]) => id)).toEqual(ids);
  expect(side.textContent).toContain(ui.clusterLimited);
  requests[1].resolve(municipalReport({ id: ids[1] }));
  await flush();
  expect(side.querySelectorAll('article')).toHaveLength(0);
  requests[0].resolve(municipalReport({ id: ids[0] }));
  await flush();
  expect(side.querySelectorAll('article')).toHaveLength(2);
  requests[2].resolve(municipalReport({ id: ids[2] }));
  await pending;
  expect(
    [...side.querySelectorAll('.detail-link')].map((link) => link.hash),
  ).toEqual(ids.map((id) => `#/reports/${id}?category=pothole`));
});

it('observes early rejections but keeps only the successful prefix before the first failure', async () => {
  const { side, requests, ids, pending } = clusterSelection();
  requests[1].reject({ status: 403 });
  requests[2].resolve(municipalReport({ id: ids[2] }));
  await flush();
  expect(side.textContent).not.toContain(ui.forbidden);
  requests[0].resolve(municipalReport({ id: ids[0] }));
  await pending;
  expect(side.querySelectorAll('article')).toHaveLength(1);
  expect(side.textContent.match(new RegExp(ui.forbidden, 'g'))).toHaveLength(1);
});

it('cancels all cluster reads and ignores late successes and failures after closing', async () => {
  const { side, requests, ids, pending } = clusterSelection();
  selection.clear();
  expect(requests.every(({ signal }) => signal.aborted)).toBe(true);
  requests[0].resolve(municipalReport({ id: ids[0] }));
  requests[1].reject(new Error('offline'));
  requests[2].resolve(municipalReport({ id: ids[2] }));
  await pending;
  expect(side.childElementCount).toBe(0);
});
