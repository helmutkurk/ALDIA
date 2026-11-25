import { afterEach, describe, expect, it, vi } from 'vitest';
import { createReportMap } from '../src/map.js';
import { report } from './fixtures.js';

let view;
afterEach(() => {
  view?.destroy();
  document.body.replaceChildren();
  vi.unstubAllGlobals();
});

function setup() {
  const region = document.createElement('section');
  const container = document.createElement('div');
  region.append(container);
  document.body.append(region);
  Object.defineProperties(container, {
    clientWidth: { value: 800, configurable: true },
    clientHeight: { value: 600, configurable: true },
  });
  vi.stubGlobal('matchMedia', () => ({ matches: true }));
  const onSelect = vi.fn();
  view = createReportMap(container, { onBoundsChange: vi.fn(), onSelect });
  return { container, onSelect };
}

describe('Leaflet map integration in jsdom', () => {
  it('centers bounds on Guatemala City, renders token classes and Spanish controls', () => {
    const { container, onSelect } = setup();
    const [west, south, east, north] = view.getBbox();
    expect((west + east) / 2).toBeCloseTo(-90.5069, 3);
    expect((south + north) / 2).toBeCloseTo(14.6349, 2);
    view.renderReports([report()]);
    expect(
      container.querySelector('.status-pin--verified').dataset.letter,
    ).toBe('A');
    expect(
      container
        .querySelector('.leaflet-control-zoom-in')
        .getAttribute('aria-label'),
    ).toBe('Acercar');
    container.querySelector('.report-marker').click();
    expect(onSelect).toHaveBeenCalledWith(report().id);
    expect(container.querySelector('.leaflet-popup').textContent).toContain(
      'no es una verificación real',
    );
  });

  it('preserves focus inside an open popup on refresh and returns it to the list on Escape', () => {
    const { container } = setup();
    const button = document.createElement('button');
    button.textContent = 'Bache';
    document.body.append(button);
    view.renderReports([report()]);
    button.focus();
    view.focusReport(report().id);
    expect(document.activeElement.tagName).toBe('H2');
    view.renderReports([report()]);
    expect(document.activeElement.tagName).toBe('H2');
    container.dispatchEvent(
      new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }),
    );
    expect(container.querySelector('.leaflet-popup')).toBeNull();
    expect(document.activeElement).toBe(button);
  });
});

it('flies to a searched place using reduced motion and retains bounds after size refresh', () => {
  const { container } = setup();
  view.flyToPlace({ latitude: 14.56, longitude: -90.73 });
  const before = view.getBbox();
  expect((before[0] + before[2]) / 2).toBeCloseTo(-90.73, 3);
  expect((before[1] + before[3]) / 2).toBeCloseTo(14.56, 3);
  view.invalidateSize();
  expect(view.getBbox()).toEqual(before);
  expect(container.getAttribute('aria-label')).toContain('Mapa');
});

it('ignores window and element resizes while a retained map is hidden', () => {
  let resizeElement;
  vi.stubGlobal(
    'ResizeObserver',
    class {
      constructor(callback) {
        resizeElement = callback;
      }
      observe() {}
      disconnect() {}
    },
  );
  const { container } = setup();
  view.flyToPlace({ latitude: 14.56, longitude: -90.73 });
  const before = view.getBbox();
  let hidden = true;
  // Leaflet caches its size; while hidden, neither callback may invalidate it.
  Object.defineProperties(container, {
    clientWidth: { get: () => (hidden ? 0 : 800), configurable: true },
    clientHeight: { get: () => (hidden ? 0 : 600), configurable: true },
  });
  window.dispatchEvent(new window.Event('resize'));
  resizeElement();
  expect(view.getBbox()).toEqual(before);
  hidden = false;
  view.invalidateSize();
  expect(view.getBbox()).toEqual(before);
});

it('renders cluster counts, zooms by click and opens members only at maximum zoom', () => {
  const region = document.createElement('section');
  const container = document.createElement('div');
  region.append(container);
  document.body.append(region);
  Object.defineProperties(container, {
    clientWidth: { value: 800 },
    clientHeight: { value: 600 },
  });
  const onCluster = vi.fn();
  view = createReportMap(container, {
    onBoundsChange: vi.fn(),
    onSelect: vi.fn(),
    onCluster,
    zoom: 17,
  });
  const cluster = {
    lat: 14.6349,
    lon: -90.5069,
    count: 12,
    ids: [report().id],
  };
  view.renderClusters([cluster]);
  expect(container.querySelector('.cluster-count').textContent).toBe('12');
  container.querySelector('.cluster-marker').click();
  expect(view.getZoom()).toBe(19);
  expect(onCluster).not.toHaveBeenCalled();
  container.querySelector('.cluster-marker').click();
  expect(onCluster).toHaveBeenCalledWith(cluster);
  view.renderClusters(
    [{ ...cluster, count: 1 }],
    [report({ state: 'programado', state_group: 'in_work' })],
  );
  expect(container.querySelector('.cluster-marker')).toBeNull();
  expect(container.querySelector('.state-pin--in_work').dataset.letter).toBe(
    'T',
  );
});

it('enlarges the selected pin and flies to a row outside the hydrated markers', () => {
  const { container } = setup();
  view.renderReports([report()]);
  view.focusReport(report().id);
  expect(container.querySelector('.report-marker--selected')).not.toBeNull();
  container.dispatchEvent(
    new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }),
  );
  expect(container.querySelector('.report-marker--selected')).toBeNull();
  const other = report({
    id: '12345678-1234-4234-8234-123456789abd',
    latitude: 14.56,
    longitude: -90.73,
  });
  view.focusReport(other.id, other);
  const bounds = view.getBbox();
  expect((bounds[0] + bounds[2]) / 2).toBeCloseTo(-90.73, 3);
});

it('keeps a real area while the map starts hidden, as on phones', () => {
  const region = document.createElement('section');
  const container = document.createElement('div');
  region.append(container);
  document.body.append(region);
  Object.defineProperties(container, {
    clientWidth: { value: 0, configurable: true },
    clientHeight: { value: 0, configurable: true },
  });
  view = createReportMap(container, {
    onBoundsChange: vi.fn(),
    onSelect: vi.fn(),
  });
  const [west, south, east, north] = view.getBbox();
  expect(east - west).toBeGreaterThan(0.01);
  expect(north - south).toBeGreaterThan(0.01);
  expect((west + east) / 2).toBeCloseTo(-90.5069, 3);
  view.setViewBounds([-90.6, 14.55, -90.45, 14.7]);
  expect(view.getZoom()).toBeGreaterThan(9);
});
