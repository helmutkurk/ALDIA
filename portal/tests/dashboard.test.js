import { afterEach, describe, expect, it, vi } from 'vitest';
import { createDashboard, periodDates } from '../src/dashboard.js';
import { createApiClient } from '../src/api.js';

let page;
afterEach(() => {
  page?.destroy();
  document.body.replaceChildren();
  vi.useRealTimers();
});
const NOW = new Date('2026-11-20T12:00:00Z');
const now = () => NOW;
const last30 = periodDates(30, NOW);

describe('legacy statistics', () => {
  it('loads filtered stats for the last 30 days, renders labelled bars and exports identical filters', async () => {
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
    page = createDashboard(root, { api, filters, now });
    await flushAll();
    const scope = { ...filters, ...last30.current, include_old: true };
    expect(api.getStats).toHaveBeenCalledWith(scope, {
      signal: expect.any(AbortSignal),
    });
    expect(root.textContent).toContain('Total de reportes: 2');
    expect(root.textContent).toContain('Bache');
    expect(root.textContent).toContain('Verificado');
    expect(root.querySelectorAll('meter')).toHaveLength(13);
    expect(api.getCsvUrl).toHaveBeenCalledWith({
      ...scope,
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
    page = createDashboard(root, { api, filters: {}, now });
    await flushAll();
    expect(root.querySelector('[role="alert"]')).not.toBeNull();
    api.getStats.mockResolvedValue({
      total: 0,
      by_category: {},
      by_status: {},
      by_resolution: {},
    });
    root.querySelector('.retry-button').click();
    await flushAll();
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

const categories = [
  {
    category: 'pothole',
    total: 8,
    resueltos: 4,
    abiertos: 3,
    cerrados: 1,
    mediana_reparacion_horas: 6,
    p90_reparacion_horas: 17,
    n_resueltos: 4,
  },
  {
    category: 'open_drain',
    total: 1,
    resueltos: 0,
    abiertos: 1,
    cerrados: 0,
    mediana_reparacion_horas: null,
    p90_reparacion_horas: null,
    n_resueltos: 0,
  },
];
const kpis = (root) =>
  Object.fromEntries(
    [...root.querySelectorAll('.stat-kpi')].map((card) => [
      card.querySelector('.stat-kpi-label').textContent,
      [
        card.querySelector('.stat-kpi-value').textContent,
        card.querySelector('.stat-kpi-foot').textContent,
      ],
    ]),
  );
const csvUrl = (query) => `/api/reports.csv?${new URLSearchParams(query)}`;

describe('statistics page (mockup layout)', () => {
  it('compares the last 30 days with the 30 days before, in Guatemala dates', async () => {
    const root = document.createElement('section');
    document.body.append(root);
    const previous = municipalStats({
      recibidos: 16,
      tasa_resolucion: 0.25,
      resolucion_horas: { median: 36, p90: 60, mean: 40, n: 4 },
      primera_respuesta_horas: { median: 2, p90: 6, n: 10 },
    });
    const api = {
      getStats: vi.fn(async (query) =>
        query.created_from === last30.current.created_from
          ? municipalStats({ por_categoria: categories })
          : previous,
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: { assignee: 'A' }, now });
    await flushAll();
    expect(last30).toEqual({
      current: { created_from: '2026-10-22', created_to: '2026-11-20' },
      previous: { created_from: '2026-09-22', created_to: '2026-10-21' },
    });
    expect(periodDates(30, new Date('2026-12-01T01:00:00Z')).current).toEqual({
      created_from: '2026-11-01',
      created_to: '2026-11-30',
    });
    expect(api.getStats).toHaveBeenCalledTimes(2);
    expect(api.getStats.mock.calls[1][0]).toEqual({
      assignee: 'A',
      ...last30.previous,
      include_old: true,
    });
    const values = kpis(root);
    expect(values.Recibidos[0]).toBe('20');
    expect(values.Recibidos[1]).toContain('+25 %');
    expect(values['Tasa de resolución'][0]).toBe('31.3 %');
    expect(values['Tasa de resolución'][1]).toContain('+6.3 pts');
    expect(values['Tasa de resolución'][1]).toContain('n = 16');
    expect(values['Mediana de reparación'][0]).toBe('0.5 d');
    expect(values['Mediana de reparación'][1]).toContain('−1.0 d');
    expect(
      root.querySelector('.stat-kpi:nth-child(3) .stat-delta').className,
    ).toContain('good');
    expect(values['Primera respuesta'][0]).toBe('2 h');
    expect(values['Primera respuesta'][1]).toContain('±0 h');
    expect(root.querySelector('[aria-pressed="true"]').textContent).toBe(
      '30 días',
    );
    expect(document.activeElement).toBe(root.querySelector('h1'));
  });

  it('switches to the full history without comparison and to 90 days', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi.fn().mockResolvedValue(municipalStats()),
      getCsvUrl: vi.fn(csvUrl),
    };
    page = createDashboard(root, { api, filters: {}, now });
    await flushAll();
    const button = (text) =>
      [...root.querySelectorAll('.stat-periods button')].find(
        (node) => node.textContent === text,
      );
    button('Todo').click();
    await flushAll();
    expect(api.getStats).toHaveBeenLastCalledWith(
      { include_old: true },
      { signal: expect.any(AbortSignal) },
    );
    expect(kpis(root).Recibidos[1]).toContain('Sin periodo de comparación');
    expect(root.querySelector('[download]').href).not.toContain('created_from');
    button('90 días').click();
    await flushAll();
    const dates = periodDates(90, NOW);
    expect(api.getStats.mock.calls.at(-2)[0]).toEqual({
      ...dates.current,
      include_old: true,
    });
    expect(button('90 días').getAttribute('aria-pressed')).toBe('true');
  });

  it('keeps explicit filter dates and every filter for stats, CSV and list links', async () => {
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
      getStats: vi
        .fn()
        .mockResolvedValue(municipalStats({ por_categoria: categories })),
      getCsvUrl: vi.fn(csvUrl),
    };
    page = createDashboard(root, { api, filters, now });
    await flushAll();
    expect(api.getStats).toHaveBeenCalledOnce();
    expect(api.getStats).toHaveBeenCalledWith(filters, {
      signal: expect.any(AbortSignal),
    });
    expect(root.querySelector('[aria-pressed="true"]')).toBeNull();
    const select = root.querySelector('select');
    select.value = 'semicolon';
    select.dispatchEvent(new window.Event('change'));
    expect(api.getCsvUrl).toHaveBeenLastCalledWith({
      ...filters,
      delimiter: 'semicolon',
    });
    const link = root.querySelector('.stat-frequency a');
    const params = new URLSearchParams(link.hash.split('?')[1]);
    expect(params.get('category')).toBe('pothole');
    expect(params.get('assignee')).toBe('<img src=x>');
    expect(params.get('created_from')).toBe('2026-11-01');
    expect(root.querySelector('img')).toBeNull();
  });

  it('draws the weekly trend with totals and a text table that never interprets week strings', async () => {
    const root = document.createElement('section');
    const hostile = '<img src=x onerror=alert(1)>';
    const api = {
      getStats: vi.fn().mockResolvedValue(
        municipalStats({
          weekly: [
            { week: '2026-W46', recibidos: 8, resueltos: 1 },
            { week: hostile, recibidos: 12, resueltos: 4 },
          ],
        }),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: {}, now });
    await flushAll();
    const trend = root.querySelector('.stat-trend');
    expect(trend.querySelectorAll('svg polyline')).toHaveLength(2);
    expect(trend.querySelector('svg').getAttribute('aria-hidden')).toBe('true');
    expect(trend.querySelector('.weekly-table').textContent).toContain(hostile);
    expect(trend.textContent).toContain('S46');
    expect(
      [...trend.querySelectorAll('.stat-total-value')].map(
        (node) => node.textContent,
      ),
    ).toEqual(['20', '5', '2']);
    expect(root.querySelector('img')).toBeNull();
  });

  it('shows an empty trend message and unavailable values, never zero', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi.fn().mockResolvedValue(
        municipalStats({
          tasa_resolucion: null,
          sla_cumplido: null,
          resolucion_horas: { median: null, p90: null, mean: null, n: 0 },
          weekly: [],
          por_categoria: [categories[1]],
        }),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: {}, now });
    await flushAll();
    expect(root.querySelector('.stat-trend').textContent).toContain(
      'No hay semanas con datos',
    );
    expect(root.querySelector('.stat-trend svg')).toBeNull();
    expect(kpis(root)['Tasa de resolución'][0]).toBe('Sin datos');
    expect(kpis(root)['Mediana de reparación'][0]).toBe('Sin datos');
    expect(root.querySelector('.stat-repair').textContent).toContain(
      'Todavía no hay reportes resueltos',
    );
    expect(root.querySelector('.stat-times').textContent).toContain(
      'Sin datos',
    );
  });

  it('renders repair bars with p90 markers, stacked frequency, ages and attention times', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi
        .fn()
        .mockResolvedValue(municipalStats({ por_categoria: categories })),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: {}, now });
    await flushAll();
    const repair = root.querySelector('.stat-repair');
    expect(repair.querySelectorAll('.stat-bar')).toHaveLength(1);
    expect(repair.querySelector('.stat-p90').style.left).toBe('100%');
    expect(repair.querySelector('.stat-row-value').textContent).toBe('0.3 d');
    const frequency = root.querySelectorAll('.stat-frequency .stat-row');
    expect(frequency).toHaveLength(2);
    expect(frequency[0].querySelectorAll('.stat-seg')).toHaveLength(3);
    expect(frequency[0].querySelector('.stat-row-value').textContent).toBe('8');
    const ages = root.querySelector('.stat-ages');
    expect(
      [...ages.querySelectorAll('.stat-column-value')].map(
        (node) => node.textContent,
      ),
    ).toEqual(['2', '3', '2', '1']);
    expect(ages.querySelector('.stat-column-bar--late')).not.toBeNull();
    expect(ages.textContent).toContain('1 caso lleva más de 30 días abierto.');
    const times = root.querySelector('.stat-times').textContent;
    expect(times).toContain('12 h');
    expect(times).toContain('48 h');
    expect(times).toContain('80.0 %');
    expect(times).toContain('n 5');
    expect(root.querySelector('.stat-zone-note').textContent).toContain(
      'desglose por zona',
    );
  });

  it('loads actual joint category/group counts only when the table is opened', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi.fn(async (query) =>
        municipalStats({
          by_state_group: query.category === 'pothole' ? { open: 7 } : {},
        }),
      ),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, {
      api,
      filters: { assignee: 'Cuadrilla A' },
      now,
    });
    await flushAll();
    expect(api.getStats).toHaveBeenCalledTimes(2);
    const details = root.querySelector('.category-group-detail');
    details.open = true;
    details.dispatchEvent(new window.Event('toggle'));
    await flushAll();
    expect(api.getStats).toHaveBeenCalledTimes(8);
    expect(api.getStats.mock.calls[2][0]).toMatchObject({
      assignee: 'Cuadrilla A',
      ...last30.current,
    });
    const rows = [...root.querySelectorAll('.category-groups tbody tr')];
    const pothole = rows.find(
      (row) => row.querySelector('th').textContent === 'Bache',
    );
    expect(pothole.querySelectorAll('td')[1].textContent).toBe('7');
  });

  it('still renders when the comparison request fails', async () => {
    const root = document.createElement('section');
    const api = {
      getStats: vi
        .fn()
        .mockResolvedValueOnce(municipalStats())
        .mockRejectedValueOnce(new Error('offline')),
      getCsvUrl: vi.fn(() => '/api/reports.csv'),
    };
    page = createDashboard(root, { api, filters: {}, now });
    await flushAll();
    expect(root.querySelector('[role="alert"]')).toBeNull();
    expect(kpis(root).Recibidos).toEqual(['20', 'Sin periodo de comparación']);
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
    page = createDashboard(root, { api, filters: {}, now });
    page.destroy();
    resolve(municipalStats());
    await flushAll();
    expect(root.childElementCount).toBe(0);
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
  expect(root.querySelectorAll('.stat-kpi')).toHaveLength(4);
  const requested = new URL(fetchImpl.mock.calls[0][0]);
  expect(requested.pathname).toBe('/api/stats');
  const csv = new URL(root.querySelector('[download]').href);
  for (const [key, value] of Object.entries(filters)) {
    expect(requested.searchParams.get(key)).toBe(String(value));
    expect(csv.searchParams.get(key)).toBe(String(value));
  }
});
