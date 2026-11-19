import { afterEach, describe, expect, it, vi } from 'vitest';
import { createDashboard } from '../src/dashboard.js';

let page;
afterEach(() => {
  page?.destroy();
  document.body.replaceChildren();
});
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

describe('dashboard', () => {
  it('loads filtered stats, renders labelled bars and exports identical filters', async () => {
    const root = document.createElement('section');
    const filters = {
      bbox: [-91, 14, -90, 15],
      category: 'pothole',
      status: 'verified',
      resolution: 'open',
    };
    const api = {
      getStats: vi.fn().mockResolvedValue({
        total: 2,
        by_category: { pothole: 2 },
        by_status: { verified: 2 },
        by_resolution: { open: 2 },
      }),
      getCsvUrl: vi.fn(
        () => 'http://localhost/api/reports.csv?resolution=open',
      ),
    };
    page = createDashboard(root, { api, filters });
    await flush();
    expect(api.getStats).toHaveBeenCalledWith(filters, {
      signal: expect.any(AbortSignal),
    });
    expect(root.textContent).toContain('Total de reportes: 2');
    expect(root.textContent).toContain('Bache');
    expect(root.textContent).toContain('Verificado');
    expect(root.textContent).toContain('Abierto');
    expect(root.querySelectorAll('meter')).toHaveLength(12);
    expect(api.getCsvUrl).toHaveBeenCalledWith(filters);
    expect(root.querySelector('[download]').textContent).toBe('Descargar CSV');
  });
  it('shows errors with retry and supports zero totals', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi.fn().mockRejectedValue(new Error('offline')),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: {} });
    await flush();
    expect(root.querySelector('[role="alert"]')).not.toBeNull();
    api.getStats.mockResolvedValue({
      total: 0,
      by_category: {},
      by_status: {},
      by_resolution: {},
    });
    root.querySelector('button').click();
    await flush();
    expect(root.textContent).toContain('Total de reportes: 0');
    expect(root.querySelector('meter').value).toBe(0);
  });
});
