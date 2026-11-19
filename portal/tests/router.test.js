import { afterEach, describe, expect, it, vi } from 'vitest';
import { createRouter, parseRoute } from '../src/router.js';
import { report } from './fixtures.js';

let router;
afterEach(() => {
  router?.destroy();
  window.history.replaceState(null, '', '/');
});

describe('hash routes', () => {
  it('parses only the map, dashboard and UUID detail routes', () => {
    expect(parseRoute('#/')).toEqual({ name: 'map' });
    expect(parseRoute('#/panel')).toEqual({ name: 'dashboard' });
    expect(parseRoute(`#/reports/${report().id}`)).toEqual({
      name: 'report',
      id: report().id,
    });
    expect(parseRoute('#/reports/../../photo').name).toBe('not-found');
    expect(parseRoute('#/missing').name).toBe('not-found');
  });

  it('handles initial deep links, hash navigation and teardown', () => {
    window.history.replaceState(null, '', `/#/reports/${report().id}`);
    const onRoute = vi.fn();
    router = createRouter(onRoute);
    expect(onRoute).toHaveBeenLastCalledWith({
      name: 'report',
      id: report().id,
    });
    window.history.replaceState(null, '', '/#/panel');
    window.dispatchEvent(new window.HashChangeEvent('hashchange'));
    expect(onRoute).toHaveBeenLastCalledWith({ name: 'dashboard' });
    router.destroy();
    onRoute.mockClear();
    window.dispatchEvent(new window.HashChangeEvent('hashchange'));
    expect(onRoute).not.toHaveBeenCalled();
  });
});
