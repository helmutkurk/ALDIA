import { afterEach, describe, expect, it, vi } from 'vitest';
import { createDashboard } from '../src/dashboard.js';
import { createApiClient } from '../src/api.js';

let page;
afterEach(() => {
  page?.destroy();
  document.body.replaceChildren();
  vi.useRealTimers();
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
    expect(root.querySelectorAll('meter')).toHaveLength(13);
    expect(api.getCsvUrl).toHaveBeenCalledWith({
      ...filters,
      delimiter: 'comma',
    });
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

/** Synthetic aggregate counts deliberately differ from the legacy total. */
function municipalStats(overrides = {}) {
  return {
    total: 20,
    by_category: { pothole: 20 },
    by_status: { verified: 20 },
    by_resolution: { open: 20 },
    recibidos: 20,
    rechazados_verificador: 2,
    abiertos: 8,
    resueltos: 5,
    cerrados_sin_solucion: 7,
    tasa_resolucion: 0.3125,
    resolucion_horas: { median: 12, p90: 48, mean: 18, n: 5 },
    primera_respuesta_horas: { median: 2, p90: 8, n: 12 },
    antiguedad_abiertos: { '0-2': 2, '3-7': 3, '8-30': 2, '>30': 1 },
    sla_cumplido: 0.8,
    vencidos: 3,
    by_state: {
      nuevo: 4,
      en_proceso: 4,
      resuelto: 5,
      duplicado: 3,
      fuera_de_competencia: 1,
      no_procede: 1,
      rechazado_verificador: 2,
    },
    by_state_group: { open: 4, in_work: 4, resolved: 5, closed: 7 },
    weekly: [
      { week: '2026-W46', recibidos: 8, resueltos: 1 },
      { week: '2026-W47', recibidos: 12, resueltos: 4 },
    ],
    ...overrides,
  };
}

const flushAll = async () => {
  for (let i = 0; i < 12; i++) await Promise.resolve();
};

describe('municipal dashboard', () => {
  it('renders API metric formulas, samples, ages and weekly SVG with text alternative', async () => {
    vi.useFakeTimers();
    const root = document.createElement('section');
    const stats = municipalStats();
    const api = {
      getStats: vi.fn(
        () => new Promise((resolve) => setTimeout(() => resolve(stats), 25)),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: { category: 'pothole' } });
    expect(root.getAttribute('aria-busy')).toBe('true');
    await vi.advanceTimersByTimeAsync(25);
    await flushAll();
    const values = Object.fromEntries(
      [...root.querySelectorAll('.metric-card')].map((card) => [
        card.querySelector('dt').textContent,
        card.querySelector('dd').textContent,
      ]),
    );
    expect(values.Recibidos).toBe('20');
    expect(values.Resueltos).toBe('5');
    expect(values['Tasa de resolución']).toBe('31.3 %n = 16');
    expect(values['Mediana de resolución']).toBe('12 hn = 5');
    expect(values['p90 de resolución']).toBe('48 hn = 5');
    expect(values['Primera respuesta: mediana']).toBe('2 hn = 12');
    expect(values['SLA cumplido']).toBe('80 %n = 5');
    expect(root.querySelector('.age-buckets').textContent).toContain(
      '>30 días: 1',
    );
    expect(root.querySelectorAll('svg polyline')).toHaveLength(2);
    expect(root.querySelector('.weekly-table').textContent).toContain(
      '2026-W47124',
    );
    expect(root.querySelectorAll('.category-groups tbody tr')).toHaveLength(1);
    expect(api.getStats).toHaveBeenCalledTimes(1);
    expect(root.getAttribute('aria-busy')).toBe('false');
  });

  it('preserves filter scope for CSV delimiters and exact category/group click-throughs', async () => {
    const root = document.createElement('section');
    const filters = {
      bbox: [-91, 14, -90, 15],
      category: 'pothole',
      state_group: 'open',
      created_from: '2026-11-01',
      assignee: '<img src=x>',
      sort: 'oldest',
      include_old: true,
    };
    const api = {
      getStats: vi.fn().mockResolvedValue(municipalStats()),
      getCsvUrl: vi.fn(
        (query) => `/api/reports.csv?${new URLSearchParams(query)}`,
      ),
    };
    page = createDashboard(root, { api, filters });
    await flushAll();
    const select = root.querySelector('select');
    select.value = 'semicolon';
    select.dispatchEvent(new window.Event('change'));
    expect(api.getCsvUrl).toHaveBeenLastCalledWith({
      ...filters,
      delimiter: 'semicolon',
    });
    expect(root.querySelector('[download]').href).toContain(
      'delimiter=semicolon',
    );
    const link = root.querySelector('.category-groups tbody td a');
    const params = new URLSearchParams(link.hash.split('?')[1]);
    expect(params.get('category')).toBe('pothole');
    expect(params.get('state_group')).toBe('open');
    expect(params.get('assignee')).toBe('<img src=x>');
    expect(params.get('created_from')).toBe('2026-11-01');
    expect(root.querySelector('img')).toBeNull();
  });

  it('obtains actual joint category/group counts without fabricating a cross product', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi.fn(async (query) =>
        municipalStats({
          by_state_group: query.category === 'pothole' ? { open: 7 } : {},
        }),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: { assignee: 'Cuadrilla A' } });
    await flushAll();
    expect(api.getStats).toHaveBeenCalledTimes(7);
    const rows = [...root.querySelectorAll('.category-groups tbody tr')];
    const pothole = rows.find(
      (row) => row.querySelector('th').textContent === 'Bache',
    );
    expect(pothole.querySelectorAll('td')[1].textContent).toBe('7');
    expect(
      rows
        .find((row) => row.querySelector('th').textContent !== 'Bache')
        .querySelectorAll('td')[1].textContent,
    ).toBe('0');
  });

  it('shows undefined ratios as unavailable and does not interpret hostile week strings', async () => {
    const root = document.createElement('section');
    const hostile = '<img src=x onerror=alert(1)>';
    const api = {
      getStats: vi.fn().mockResolvedValue(
        municipalStats({
          recibidos: 0,
          tasa_resolucion: null,
          sla_cumplido: null,
          resolucion_horas: { median: null, p90: null, mean: null, n: 0 },
          weekly: [{ week: hostile, recibidos: 0, resueltos: 0 }],
        }),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: { category: 'pothole' } });
    await flushAll();
    expect(root.querySelector('.metric-cards').textContent).toContain(
      'Sin datos',
    );
    expect(root.querySelector('.weekly-table').textContent).toContain(hostile);
    expect(root.querySelector('img')).toBeNull();
  });

  it('draws the band, the all-time chart with end numbers, sparklines and the top five', async () => {
    const root = document.createElement('section');
    const weeks = [
      { week: '2026-W44', recibidos: 2, resueltos: 0 },
      { week: '2026-W45', recibidos: 5, resueltos: 1 },
      { week: '2026-W46', recibidos: 8, resueltos: 1 },
      { week: '2026-W47', recibidos: 12, resueltos: 4 },
    ];
    const api = {
      getStats: vi.fn(async () =>
        municipalStats({
          total: 27,
          recibidos: 27,
          resueltos: 6,
          by_category: {
            pothole: 10,
            graffiti: 7,
            sidewalk: 4,
            street_light: 3,
            open_drain: 2,
            accessibility: 1,
          },
          weekly: weeks,
        }),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: {} });
    await flushAll();
    expect(root.classList.contains('page--dashboard')).toBe(true);
    expect(root.querySelector('.dash-band h1').textContent).toBe(
      'Panel de reportes',
    );
    // Two cumulative lines; sparklines use paths so the chart keeps exactly two polylines.
    expect(root.querySelectorAll('svg polyline')).toHaveLength(2);
    const ends = [...root.querySelectorAll('.chart-total')].map(
      (node) => node.textContent,
    );
    expect(ends[0]).toContain('27');
    expect(ends[0]).toContain('reportes recibidos');
    expect(ends[1]).toContain('6');
    const cumulative = root
      .querySelector('.weekly-line--recibidos')
      .getAttribute('points')
      .split(' ');
    expect(cumulative).toHaveLength(4);
    // Last-week block: only series the contract provides (no invented "updates").
    const sparks = [...root.querySelectorAll('.spark-item')];
    expect(
      sparks.map((node) => node.querySelector('.spark-label').textContent),
    ).toEqual(['Recibidos', 'Resueltos']);
    expect(sparks[0].querySelector('.spark-value').textContent).toBe('12');
    expect(sparks[0].querySelector('svg').getAttribute('aria-label')).toContain(
      '2, 5, 8, 12',
    );
    expect(root.textContent).not.toContain('actualizaciones');
    const top = [...root.querySelectorAll('.top-categories li a')].map(
      (node) => node.textContent,
    );
    expect(top).toHaveLength(5);
    expect(top[0]).toBe('Bache: 10');
    expect(top.join(' ')).not.toContain('Accesibilidad');
    expect(root.querySelector('.zone-link').hash).toBe('#/');
    expect(root.querySelector('.metric-cards')).not.toBeNull();
    page.destroy();
    expect(root.classList.contains('page--dashboard')).toBe(false);
  });

  it('shows an empty chart message and keeps the page usable without weekly data', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi.fn(async () =>
        municipalStats({ weekly: [], by_category: {}, total: 0, recibidos: 0 }),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: {} });
    await flushAll();
    expect(root.textContent).toContain('No hay semanas con datos');
    expect(root.querySelector('.top-categories').textContent).toContain(
      'No hay reportes por categoría',
    );
    expect(root.querySelector('svg polyline')).toBeNull();
  });

  it('ignores late statistics after disposal', async () => {
    let resolve;
    const root = document.createElement('section');
    const api = {
      getStats: vi.fn(
        () =>
          new Promise((done) => {
            resolve = done;
          }),
      ),
      getCsvUrl: vi.fn(),
    };
    page = createDashboard(root, { api, filters: {} });
    page.destroy();
    resolve(municipalStats());
    await flushAll();
    expect(root.childElementCount).toBe(0);
    expect(api.getCsvUrl).not.toHaveBeenCalled();
  });
});

it('integrates dashboard and API through mocked fetch with every CSV filter retained', async () => {
  vi.useFakeTimers();
  const root = document.createElement('section');
  const fetchImpl = vi.fn(
    async () => new Response(JSON.stringify(municipalStats()), { status: 200 }),
  );
  const api = createApiClient({ fetchImpl });
  const filters = {
    bbox: [-91, 14, -90, 15],
    category: 'pothole',
    state_group: 'open',
    created_from: '2026-11-01',
    created_to: '2026-11-19',
    assignee: 'Cuadrilla A',
    sort: 'updated',
    include_old: true,
  };
  page = createDashboard(root, { api, filters });
  await vi.advanceTimersByTimeAsync(0);
  await flushAll();
  expect(root.querySelector('.metric-cards')).not.toBeNull();
  const requested = new URL(fetchImpl.mock.calls[0][0]);
  expect(requested.pathname).toBe('/api/stats');
  const csv = new URL(root.querySelector('[download]').href);
  for (const [key, value] of Object.entries(filters)) {
    expect(requested.searchParams.get(key)).toBe(String(value));
    expect(csv.searchParams.get(key)).toBe(String(value));
  }
  const selector = root.querySelector('select');
  selector.value = 'semicolon';
  selector.dispatchEvent(new window.Event('change'));
  expect(
    new URL(root.querySelector('[download]').href).searchParams.get(
      'delimiter',
    ),
  ).toBe('semicolon');
});
