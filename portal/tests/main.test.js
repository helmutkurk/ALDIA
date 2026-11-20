import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createPortal } from '../src/main.js';
import { report } from './fixtures.js';

let app;
beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  app?.destroy();
  document.body.replaceChildren();
  window.history.replaceState(null, '', '/');
  vi.useRealTimers();
});

function setup(routed = false) {
  const panelElement = document.createElement('aside');
  const mapElement = document.createElement('div');
  const workspaceElement = document.createElement('div');
  const pageElement = document.createElement('section');
  const headerElement = document.createElement('header');
  workspaceElement.append(panelElement, mapElement);
  document.body.append(headerElement, workspaceElement, pageElement);
  let callbacks;
  const map = {
    getBbox: vi.fn(() => [-91, 14, -90, 15]),
    renderReports: vi.fn(),
    focusReport: vi.fn(),
    flyToPlace: vi.fn(),
    invalidateSize: vi.fn(),
    destroy: vi.fn(),
  };
  const api = {
    getReports: vi.fn().mockResolvedValue({ items: [], total: 0 }),
    getReport: vi.fn().mockResolvedValue(report()),
    getStats: vi.fn().mockResolvedValue({
      total: 0,
      by_category: {},
      by_status: {},
      by_resolution: {},
    }),
    getCsvUrl: vi.fn(() => '/api/reports.csv'),
  };
  app = createPortal({
    panelElement,
    mapElement,
    api,
    ...(routed
      ? {
          headerElement,
          pageElement,
          workspaceElement,
          locationMapFactory: () => ({ destroy: vi.fn() }),
        }
      : {}),
    mapFactory: (_element, handlers) => {
      callbacks = handlers;
      return map;
    },
  });
  return {
    panelElement,
    callbacks,
    map,
    api,
    workspaceElement,
    pageElement,
    headerElement,
  };
}

describe('map and request coordination', () => {
  it('debounces bounds changes for 300 ms and sends the latest bounds', async () => {
    const { callbacks, api, map } = setup();
    await vi.advanceTimersByTimeAsync(299);
    expect(api.getReports).not.toHaveBeenCalled();
    callbacks.onBoundsChange();
    map.getBbox.mockReturnValue([-90.6, 14.5, -90.4, 14.7]);
    await vi.advanceTimersByTimeAsync(299);
    expect(api.getReports).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(api.getReports).toHaveBeenCalledExactlyOnceWith(
      {
        bbox: [-90.6, 14.5, -90.4, 14.7],
        category: '',
        status: '',
        resolution: '',
      },
      { signal: expect.any(AbortSignal) },
    );
  });

  it('aborts old requests and ignores responses that arrive out of order', async () => {
    const { callbacks, api } = setup();
    let resolveOld;
    api.getReports.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveOld = resolve;
        }),
    );
    await vi.advanceTimersByTimeAsync(300);
    const oldSignal = api.getReports.mock.calls[0][1].signal;
    callbacks.onBoundsChange();
    expect(oldSignal.aborted).toBe(true);
    await vi.advanceTimersByTimeAsync(300);
    resolveOld({ items: [report()], total: 1 });
    await Promise.resolve();
    expect(app.store.getState().reports).toEqual([]);
  });

  it('reloads with selected filters and flies to a selected report', async () => {
    const { panelElement, api, map } = setup();
    api.getReports.mockResolvedValue({ items: [report()], total: 1 });
    await vi.advanceTimersByTimeAsync(300);
    panelElement.querySelector('.report-button').click();
    expect(map.focusReport).toHaveBeenCalledWith(report().id, report());
    const category = panelElement.querySelector('#category-filter');
    category.value = 'pothole';
    category.dispatchEvent(new window.Event('change'));
    await vi.advanceTimersByTimeAsync(300);
    expect(api.getReports.mock.lastCall[0].category).toBe('pothole');
  });

  it('cancels pending work on teardown', async () => {
    const { api, map } = setup();
    app.destroy();
    app = null;
    await vi.advanceTimersByTimeAsync(1000);
    expect(api.getReports).not.toHaveBeenCalled();
    expect(map.destroy).toHaveBeenCalledOnce();
  });
});

function route(hash) {
  window.history.replaceState(null, '', `/${hash}`);
  window.dispatchEvent(new window.HashChangeEvent('hashchange'));
}

describe('page coordination', () => {
  it('retains the map instance, filters, reports, selection, scroll and focus across report navigation', async () => {
    const { map, api, panelElement, workspaceElement, pageElement } =
      setup(true);
    api.getReports.mockResolvedValue({ items: [report()], total: 1 });
    const resolution = panelElement.querySelector('#resolution-filter');
    resolution.value = 'open';
    resolution.dispatchEvent(new window.Event('change'));
    await vi.advanceTimersByTimeAsync(300);
    panelElement.querySelector('.report-button').click();
    const state = app.store.getState();
    const link = panelElement.querySelector('.detail-link');
    expect(link.getAttribute('href')).toContain(`#/reports/${report().id}?`);
    expect(link.getAttribute('href')).toContain('resolution=open');
    link.focus();
    panelElement.scrollTop = 120;
    route(link.getAttribute('href'));
    await Promise.resolve();
    expect(workspaceElement.hidden).toBe(true);
    expect(pageElement.textContent).toContain('Bache');
    expect(api.getReport).toHaveBeenCalledWith(report().id, {
      signal: expect.any(AbortSignal),
    });
    route(pageElement.querySelector('.back-link').getAttribute('href'));
    expect(workspaceElement.hidden).toBe(false);
    expect(pageElement.hidden).toBe(true);
    expect(map.destroy).not.toHaveBeenCalled();
    expect(app.store.getState()).toBe(state);
    expect(panelElement.scrollTop).toBe(120);
    expect(document.activeElement).toBe(link);
    await vi.advanceTimersByTimeAsync(500);
    expect(api.getReports).toHaveBeenCalledOnce();
  });

  it('passes the visible area and all current filters to dashboard stats and CSV', async () => {
    const { api, map, headerElement } = setup(true);
    app.store.setFilters({
      category: 'pothole',
      status: 'verified',
      resolution: 'fixed',
    });
    route(headerElement.querySelector('.dashboard-link').getAttribute('href'));
    await Promise.resolve();
    const filters = {
      bbox: map.getBbox(),
      category: 'pothole',
      status: 'verified',
      resolution: 'fixed',
      include_old: true,
    };
    expect(api.getStats).toHaveBeenCalledWith(filters, {
      signal: expect.any(AbortSignal),
    });
    expect(api.getCsvUrl).toHaveBeenCalledWith({
      ...filters,
      delimiter: 'comma',
    });
  });

  it('loads initial deep links and aborts a report request when going back', async () => {
    window.history.replaceState(null, '', `/#/reports/${report().id}`);
    const { api, workspaceElement } = setup(true);
    expect(api.getReport).toHaveBeenCalledOnce();
    const signal = api.getReport.mock.calls[0][1].signal;
    route('#/');
    expect(signal.aborted).toBe(true);
    expect(workspaceElement.hidden).toBe(false);
    await vi.advanceTimersByTimeAsync(300);
    expect(api.getReports).toHaveBeenCalledOnce();
  });
});

describe('site header', () => {
  it('offers the four destinations, keeps the scope and marks the current page', async () => {
    const { headerElement, panelElement } = setup(true);
    const labels = [...headerElement.querySelectorAll('nav a, nav button')].map(
      (node) => node.textContent,
    );
    expect(labels).toEqual(['Mapa', 'Triaje', 'Panel', 'Modo personal', '?']);
    expect(headerElement.querySelector('nav').getAttribute('aria-label')).toBe(
      'Principal',
    );
    expect(
      headerElement.querySelector('.map-link').getAttribute('aria-current'),
    ).toBe('page');
    app.store.setFilters({ category: 'pothole', status: '', resolution: '' });
    expect(headerElement.querySelector('.triage-link').hash).toContain(
      'category=pothole',
    );
    route('#/panel');
    expect(
      headerElement
        .querySelector('.dashboard-link')
        .getAttribute('aria-current'),
    ).toBe('page');
    expect(
      headerElement.querySelector('.map-link').hasAttribute('aria-current'),
    ).toBe(false);
    route('#/');
    panelElement.querySelector('.staff-panel').open = false;
    headerElement.querySelector('.staff-link').click();
    expect(panelElement.querySelector('.staff-panel').open).toBe(true);
    expect(document.activeElement.id).toBe('staff-username');
  });

  it('toggles between list and map with a text label', () => {
    const { panelElement, map } = setup();
    const toggle = document.querySelector('.map-toggle');
    expect(toggle.textContent).toBe('Ver mapa');
    toggle.click();
    expect(toggle.textContent).toBe('Ver lista');
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(map.invalidateSize).toHaveBeenCalled();
    expect(panelElement).toBeTruthy();
  });
});

it('requests individual status pins at zoom 15 even though the API singleton threshold is 17', async () => {
  const { api, map } = setup();
  api.getClusters = vi.fn().mockResolvedValue({ clusters: [], total: 0 });
  map.getZoom = vi.fn(() => 15);
  map.renderClusters = vi.fn();
  await vi.advanceTimersByTimeAsync(300);
  expect(api.getClusters.mock.calls[0][0].zoom).toBe(17);
  expect(map.renderClusters).toHaveBeenCalledWith([], []);
});
