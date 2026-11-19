import { afterEach, describe, expect, it, vi } from 'vitest';
import { createReportPage } from '../src/report.js';
import { report } from './fixtures.js';

let page;
afterEach(() => {
  page?.destroy();
  document.body.replaceChildren();
});
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

describe('report page', () => {
  it('renders literal hostile data, states, checks, Guatemala date and location', async () => {
    const root = document.createElement('section');
    document.body.append(root);
    const hostile = '<img src=x onerror=alert(1)>';
    const item = report({
      resolution: 'acknowledged',
      note: hostile,
      verification: {
        mode: 'stub',
        passed: false,
        checks: [
          { name: hostile, passed: false, detail: hostile },
          { name: 'place', passed: true, detail: 'GT' },
        ],
      },
    });
    const map = { destroy: vi.fn() };
    const mapFactory = vi.fn(() => map);
    page = createReportPage(root, {
      id: item.id,
      api: { getReport: vi.fn().mockResolvedValue(item) },
      mapFactory,
    });
    await flush();
    expect(root.querySelector('h1').textContent).toBe('Bache');
    expect(root.textContent).toContain(hostile);
    expect(root.querySelectorAll('img')).toHaveLength(1);
    expect(root.querySelector('script, [onerror]')).toBeNull();
    expect(root.textContent).toContain('En atención');
    expect(root.textContent).toContain('Verificado (prueba)');
    expect(root.textContent).toContain('no es una verificación real');
    expect(root.textContent).toContain('No superada');
    expect(root.querySelectorAll('.check-icon')).toHaveLength(2);
    expect(root.querySelector('time').textContent).toContain('12:30');
    expect(root.querySelector('a').getAttribute('href')).toBe('#/');
    expect(mapFactory).toHaveBeenCalledWith(
      expect.any(window.HTMLElement),
      item,
    );
    page.destroy();
    expect(map.destroy).toHaveBeenCalledOnce();
  });

  it('shows a recoverable 404 and ignores late responses after teardown', async () => {
    const root = document.createElement('section');
    const api = { getReport: vi.fn().mockRejectedValue({ status: 404 }) };
    page = createReportPage(root, { id: report().id, api });
    await flush();
    expect(root.textContent).toContain('No se encontró el reporte');
    expect(root.querySelector('button')).not.toBeNull();
    let resolve;
    api.getReport.mockImplementation(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    );
    root.querySelector('button').click();
    page.destroy();
    resolve(report());
    await flush();
    expect(root.children).toHaveLength(0);
  });
});
