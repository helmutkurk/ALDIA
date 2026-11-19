import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { createApiClient } from '../src/api.js';
import { createPortal } from '../src/main.js';
import { createReportPage } from '../src/report.js';
import { createStaffSession } from '../src/staff.js';
import { municipalReport } from './fixtures.js';

let app, page, staff;
const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
const submit = (form) =>
  form.dispatchEvent(
    new window.Event('submit', { bubbles: true, cancelable: true }),
  );
beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  app?.destroy();
  page?.destroy();
  staff?.destroy();
  app = page = staff = null;
  document.body.replaceChildren();
  window.history.replaceState(null, '', '/');
  vi.useRealTimers();
});
const flush = () => vi.advanceTimersByTimeAsync(0);

function setupPortal(fetchImpl) {
  const panelElement = document.createElement('aside');
  const mapElement = document.createElement('div');
  const workspaceElement = document.createElement('div');
  const pageElement = document.createElement('section');
  workspaceElement.append(panelElement, mapElement);
  document.body.append(workspaceElement, pageElement);
  let callbacks;
  const map = {
    getBbox: () => [-91, 14, -90, 15],
    getZoom: () => 17,
    renderReports: vi.fn(),
    renderClusters: vi.fn(),
    focusReport: vi.fn(),
    flyToPlace: vi.fn(),
    invalidateSize: vi.fn(),
    destroy: vi.fn(),
  };
  staff = createStaffSession();
  const api = createApiClient({ staff, fetchImpl });
  app = createPortal({
    panelElement,
    mapElement,
    workspaceElement,
    pageElement,
    api,
    staff,
    mapFactory: (_root, cb) => {
      callbacks = cb;
      return map;
    },
    locationMapFactory: () => ({ destroy() {} }),
  });
  return { map, callbacks, panelElement, pageElement };
}

it('loads paginated list and viewport clusters independently; hydrates singletons and opens a side panel', async () => {
  const report = municipalReport();
  const fetchImpl = vi.fn(async (url) => {
    const path = new URL(url).pathname;
    if (path.endsWith('/clusters'))
      return json({
        clusters: [
          {
            lat: report.latitude,
            lon: report.longitude,
            count: 1,
            ids: [report.id],
          },
        ],
        total: 1,
      });
    if (path.endsWith(`/${report.id}`)) return json(report);
    return json({ items: [report], total: 40, limit: 25, offset: 0 });
  });
  const { map, callbacks, panelElement } = setupPortal(fetchImpl);
  await vi.advanceTimersByTimeAsync(300);
  expect(map.renderClusters).toHaveBeenCalledWith(
    [expect.objectContaining({ count: 1 })],
    [report],
  );
  expect(map.renderReports).not.toHaveBeenCalled();
  const urls = fetchImpl.mock.calls.map(([url]) => new URL(url));
  expect(
    urls
      .find((url) => url.pathname.endsWith('/clusters'))
      .searchParams.get('zoom'),
  ).toBe('17');
  expect(
    urls
      .find((url) => url.pathname.endsWith('/reports'))
      .searchParams.get('limit'),
  ).toBe('25');
  callbacks.onSelect(report.id);
  await flush();
  expect(panelElement.querySelector('.selected-report').textContent).toContain(
    'En revisión',
  );
  expect(window.location.hash).not.toContain('/reports/');
  callbacks.onCluster({ count: 12, ids: [report.id] });
  await flush();
  expect(panelElement.querySelector('.selected-report').textContent).toContain(
    'hasta cinco',
  );
});

it('serializes every filter safely, paginates on server and restores filters from a shared URL', async () => {
  window.history.replaceState(null, '', '/#/');
  const fetchImpl = vi.fn(async (url) =>
    new URL(url).pathname.endsWith('/clusters')
      ? json({ clusters: [], total: 0 })
      : json({ items: [], total: 50 }),
  );
  const { panelElement } = setupPortal(fetchImpl);
  await vi.advanceTimersByTimeAsync(300);
  const state = panelElement.querySelector('#state-filter');
  state.value = 'nuevo';
  state.dispatchEvent(new window.Event('change', { bubbles: true }));
  const assignee = panelElement.querySelector('[name=assignee]');
  assignee.value = '<svg onload=bad>';
  assignee.dispatchEvent(new window.Event('change', { bubbles: true }));
  const old = panelElement.querySelector('[name=include_old]');
  old.checked = true;
  old.dispatchEvent(new window.Event('change', { bubbles: true }));
  await vi.advanceTimersByTimeAsync(300);
  expect(window.location.hash).toContain('state=nuevo');
  expect(window.location.hash).toContain('include_old=true');
  expect(panelElement.querySelector('svg')).toBeNull();
  expect(panelElement.querySelector('.filter-chips').textContent).toContain(
    '<svg',
  );
  [...panelElement.querySelectorAll('.pagination button')]
    .find((b) => b.textContent === 'Siguiente')
    .click();
  await vi.advanceTimersByTimeAsync(300);
  const lastList = fetchImpl.mock.calls
    .map(([url]) => new URL(url))
    .filter((url) => url.pathname.endsWith('/reports'))
    .at(-1);
  expect(lastList.searchParams.get('offset')).toBe('25');
  expect(lastList.searchParams.get('assignee')).toBe('<svg onload=bad>');
  window.history.replaceState(
    null,
    '',
    '/#/?category=graffiti&state_group=in_work&sort=oldest',
  );
  window.dispatchEvent(new window.HashChangeEvent('hashchange'));
  await vi.advanceTimersByTimeAsync(300);
  expect(panelElement.querySelector('#category-filter').value).toBe('graffiti');
  expect(panelElement.querySelector('#state-group-filter').value).toBe(
    'in_work',
  );
});

it('clears private timelines immediately when staff mode ends on a deep report link', async () => {
  const report = municipalReport({
    events: [
      {
        at: '2026-11-19T19:00:00Z',
        actor_role: 'operator',
        from_state: 'nuevo',
        to_state: 'en_revision',
        public_note: 'Público',
        internal_note: 'Solo personal',
      },
    ],
  });
  window.history.replaceState(null, '', `/#/reports/${report.id}`);
  const fetchImpl = vi.fn(async (url, options) => {
    const path = new URL(url).pathname;
    if (path.endsWith('/nearby')) return json([]);
    if (path.endsWith(`/${report.id}`))
      return json(
        options.headers['X-Staff-Token']
          ? report
          : {
              ...report,
              events: report.events.map(
                ({ internal_note: _private, ...event }) => event,
              ),
            },
      );
    return json({ items: [], total: 0 });
  });
  const { pageElement } = setupPortal(fetchImpl);
  staff.setToken('x'.repeat(32));
  await flush();
  expect(pageElement.textContent).toContain('Solo personal');
  staff.clear();
  expect(pageElement.textContent).not.toContain('Solo personal');
  await flush();
  expect(pageElement.textContent).toContain('Público');
  expect(pageElement.querySelector('.transition-form')).toBeNull();
  expect(document.querySelector('#staff-token').closest('[hidden]')).toBeNull();
});

it('renders hostile timeline and nearby data literally, selects duplicates and submits with staff header', async () => {
  const report = municipalReport({
    events: [
      {
        at: '2026-11-19T19:00:00Z',
        actor_role: 'system',
        from_state: 'nuevo',
        to_state: 'en_revision',
        public_note: '<svg onload=bad>',
      },
    ],
  });
  const duplicate = municipalReport({
    id: '22345678-1234-4234-8234-123456789abc',
    thumbnail_url: 'javascript:bad',
  });
  staff = createStaffSession();
  staff.setToken('z'.repeat(32));
  const fetchImpl = vi.fn(async (url, options) => {
    if (url.endsWith('/nearby')) return json([duplicate]);
    if (url.endsWith('/transition'))
      return json({
        ...report,
        ...JSON.parse(options.body),
        state: 'duplicado',
        state_group: 'closed',
      });
    return json(report);
  });
  const root = document.createElement('section');
  document.body.append(root);
  page = createReportPage(root, {
    id: report.id,
    staff,
    api: createApiClient({ staff, fetchImpl }),
    mapFactory: () => ({ destroy() {} }),
  });
  await flush();
  expect(root.textContent).toContain('<svg onload=bad>');
  expect(root.querySelector('[onload]')).toBeNull();
  expect(root.querySelector('.nearby-thumbnail')).toBeNull();
  [...root.querySelectorAll('button')]
    .find((b) => b.textContent === 'Marcar como duplicado')
    .click();
  expect(root.querySelector('[name=to]').value).toBe('duplicado');
  expect(root.querySelector('[name=duplicate_of]').value).toBe(duplicate.id);
  submit(root.querySelector('.transition-form'));
  await flush();
  const [, options] = fetchImpl.mock.calls.find(([url]) =>
    url.endsWith('/transition'),
  );
  expect(JSON.parse(options.body)).toEqual({
    to: 'duplicado',
    duplicate_of: duplicate.id,
  });
  expect(options.headers['X-Staff-Token']).toBe('z'.repeat(32));
});

it.each([401, 409, 503])(
  'shows Spanish detail errors for HTTP %i',
  async (status) => {
    const root = document.createElement('section');
    document.body.append(root);
    page = createReportPage(root, {
      id: municipalReport().id,
      api: createApiClient({
        fetchImpl: vi.fn(async () =>
          json({ error: { code: 'fail', message: '<img src=x>' } }, status),
        ),
      }),
      mapFactory: vi.fn(),
    });
    await flush();
    expect(root.querySelector('[role=alert]').textContent).not.toContain(
      '<img',
    );
    expect(root.querySelector('button').textContent).toBe('Volver a intentar');
  },
);

it('loads previous/next pages through the current filter and honors retained report ordering', async () => {
  const report = municipalReport();
  const second = municipalReport({
    id: '22345678-1234-4234-8234-123456789abc',
  });
  window.history.replaceState(
    null,
    '',
    `/#/reports/${report.id}?category=pothole&sort=oldest`,
  );
  const fetchImpl = vi.fn(async (url) => {
    const path = new URL(url).pathname;
    if (path.endsWith('/nearby')) return json([]);
    if (path.endsWith('/reports'))
      return json({ items: [report, second], total: 2 });
    return json(report);
  });
  const { pageElement } = setupPortal(fetchImpl);
  await flush();
  [...pageElement.querySelectorAll('.report-navigation button')]
    .find((b) => b.textContent === 'Siguiente')
    .click();
  await flush();
  expect(window.location.hash).toContain(`/reports/${second.id}?`);
  expect(window.location.hash).toContain('sort=oldest');
  expect(window.location.hash).toContain('category=pothole');
});

it('resets pagination when the viewport changes and keeps a successful list after a pin hydration failure', async () => {
  const report = municipalReport();
  let brokenPin = false;
  const fetchImpl = vi.fn(async (url) => {
    const path = new URL(url).pathname;
    if (path.endsWith('/clusters'))
      return json({
        clusters: brokenPin
          ? [
              {
                lat: 14.6,
                lon: -90.5,
                count: 1,
                ids: ['22345678-1234-4234-8234-123456789abc'],
              },
            ]
          : [],
        total: brokenPin ? 1 : 0,
      });
    if (path.endsWith('/reports')) return json({ items: [report], total: 50 });
    return json({ error: { code: 'not_found', message: 'Not found' } }, 404);
  });
  const { panelElement, callbacks, map } = setupPortal(fetchImpl);
  await vi.advanceTimersByTimeAsync(300);
  panelElement.querySelector('.pagination button:last-child').click();
  await vi.advanceTimersByTimeAsync(300);
  expect(app.store.getState().offset).toBe(25);
  brokenPin = true;
  callbacks.onBoundsChange();
  await vi.advanceTimersByTimeAsync(300);
  expect(app.store.getState().offset).toBe(0);
  expect(app.store.getState().phase).toBe('success');
  expect(panelElement.querySelector('.report-button')).not.toBeNull();
  expect(map.renderClusters).toHaveBeenLastCalledWith([]);
  expect(panelElement.textContent).toContain(
    'No se pudieron cargar los grupos',
  );
});

it('restores filtered routes without overwriting their hash and reloads the list on return', async () => {
  const report = municipalReport();
  const fetchImpl = vi.fn(async (url) => {
    const path = new URL(url).pathname;
    if (path.endsWith('/clusters')) return json({ clusters: [], total: 0 });
    if (path.endsWith('/nearby')) return json([]);
    if (path.endsWith('/reports')) return json({ items: [report], total: 1 });
    return json(report);
  });
  const { map, callbacks, pageElement, panelElement } = setupPortal(fetchImpl);
  await vi.advanceTimersByTimeAsync(300);
  map.setViewBounds = vi.fn(() => callbacks.onBoundsChange());
  const hash = `#/reports/${report.id}?category=pothole&bbox=-92,13,-89,16`;
  window.history.replaceState(null, '', `/${hash}`);
  window.dispatchEvent(new window.HashChangeEvent('hashchange'));
  await flush();
  expect(window.location.hash).toBe(hash);
  expect(map.setViewBounds).toHaveBeenCalled();
  const back = pageElement.querySelector('.back-link');
  window.history.replaceState(null, '', `/${back.getAttribute('href')}`);
  window.dispatchEvent(new window.HashChangeEvent('hashchange'));
  await vi.advanceTimersByTimeAsync(300);
  expect(app.store.getState().phase).toBe('success');
  expect(panelElement.querySelector('.report-button')).not.toBeNull();
  window.history.replaceState(null, '', '/#/');
  window.dispatchEvent(new window.HashChangeEvent('hashchange'));
  await vi.advanceTimersByTimeAsync(300);
  expect(app.store.getState().filters.category).toBe('');
});

it('refreshes retained map results after changing a report on its detail page', async () => {
  const report = municipalReport({ state: 'nuevo' });
  let current = report;
  const fetchImpl = vi.fn(async (url, options) => {
    const path = new URL(url).pathname;
    if (path.endsWith('/clusters')) return json({ clusters: [], total: 0 });
    if (path.endsWith('/nearby')) return json([]);
    if (path.endsWith('/reports')) return json({ items: [current], total: 1 });
    if (path.endsWith('/transition')) {
      current = { ...current, state: JSON.parse(options.body).to };
      return json(current);
    }
    if (path.endsWith('/photo')) return new Response(null, { status: 404 });
    return json(current);
  });
  const { panelElement, pageElement } = setupPortal(fetchImpl);
  staff.setToken('synthetic-staff-token-for-update-test');
  await vi.advanceTimersByTimeAsync(300);
  const href = panelElement.querySelector('.detail-link').getAttribute('href');
  window.history.replaceState(null, '', `/${href}`);
  window.dispatchEvent(new window.HashChangeEvent('hashchange'));
  await flush();
  submit(pageElement.querySelector('.transition-form'));
  await flush();
  expect(current.state).toBe('en_revision');
  const back = pageElement.querySelector('.back-link').getAttribute('href');
  window.history.replaceState(null, '', `/${back}`);
  window.dispatchEvent(new window.HashChangeEvent('hashchange'));
  await vi.advanceTimersByTimeAsync(300);
  expect(app.store.getState().reports[0].state).toBe('en_revision');
});
