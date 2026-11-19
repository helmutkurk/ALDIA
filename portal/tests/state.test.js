import { describe, expect, it, vi } from 'vitest';
import { createStore, filterReports } from '../src/state.js';
import { report } from './fixtures.js';

const pending = report({
  id: '22345678-1234-4234-8234-123456789abc',
  category: 'graffiti',
  status: 'pending',
  verification: null,
});

describe('report store and filters', () => {
  it('combines category and status filters without mutating input', () => {
    const reports = [report(), pending];
    expect(filterReports(reports, { category: '', status: '' })).toEqual(
      reports,
    );
    expect(
      filterReports(reports, { category: 'pothole', status: 'pending' }),
    ).toEqual([]);
    expect(
      filterReports(reports, { category: 'graffiti', status: 'pending' }),
    ).toEqual([pending]);
    expect(reports).toHaveLength(2);
  });

  it('notifies subscribers and supports unsubscribe', () => {
    const store = createStore();
    const listener = vi.fn();
    const unsubscribe = store.subscribe(listener);
    store.startLoading();
    store.setReports({ items: [report()], total: 20 });
    expect(listener).toHaveBeenCalledTimes(3);
    expect(store.getState()).toMatchObject({
      phase: 'success',
      total: 20,
      error: null,
    });
    unsubscribe();
    store.startLoading();
    expect(listener).toHaveBeenCalledTimes(3);
  });

  it('clears stale data and selection on filter changes and errors', () => {
    const store = createStore();
    store.setReports({ items: [report()], total: 1 });
    store.selectReport(report().id);
    expect(store.getState().selectedId).toBe(report().id);
    store.setFilters({ category: 'graffiti', status: 'pending' });
    expect(store.getState()).toMatchObject({
      reports: [],
      total: 0,
      selectedId: null,
    });
    store.setError({ code: 'network_error', message: 'Sin conexión' });
    expect(store.getState()).toMatchObject({
      phase: 'error',
      reports: [],
      error: { code: 'network_error' },
    });
  });

  it('preserves a selected report across refreshes only while present', () => {
    const store = createStore();
    store.setReports({ items: [report()], total: 1 });
    store.selectReport(report().id);
    store.startLoading();
    store.setReports({ items: [report()], total: 1 });
    expect(store.getState().selectedId).toBe(report().id);
    store.setReports({ items: [], total: 0 });
    expect(store.getState().selectedId).toBeNull();
  });

  it('rejects filters outside the contract', () => {
    expect(() =>
      createStore().setFilters({ category: 'other', status: '' }),
    ).toThrow(RangeError);
  });
});

it('combines resolution with category and status and rejects unknown resolutions', () => {
  const open = report();
  const fixed = report({ resolution: 'fixed' });
  expect(
    filterReports([open, fixed], {
      category: 'pothole',
      status: 'verified',
      resolution: 'fixed',
    }),
  ).toEqual([fixed]);
  const store = createStore();
  store.setFilters({ category: '', status: '', resolution: 'acknowledged' });
  expect(store.getState().filters.resolution).toBe('acknowledged');
  expect(() =>
    store.setFilters({ category: '', status: '', resolution: 'closed' }),
  ).toThrow(RangeError);
});
