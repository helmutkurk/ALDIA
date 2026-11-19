import { afterEach, describe, expect, it, vi } from 'vitest';
import { createPanel, createReportDetails } from '../src/panel.js';
import { createStore } from '../src/state.js';
import { report } from './fixtures.js';

let panel;
afterEach(() => {
  panel?.destroy();
  document.body.replaceChildren();
});

function setup() {
  const root = document.createElement('aside');
  document.body.append(root);
  const onSelect = vi.fn();
  const onFiltersChange = vi.fn();
  const onRetry = vi.fn();
  panel = createPanel(root, { onSelect, onFiltersChange, onRetry });
  const store = createStore();
  store.subscribe(panel.render);
  return { root, store, onSelect, onFiltersChange, onRetry };
}

describe('accessible panel', () => {
  it('labels filters and emits both selected values', () => {
    const { root, onFiltersChange } = setup();
    const category = root.querySelector('#category-filter');
    const status = root.querySelector('#status-filter');
    expect(root.querySelector('label[for="category-filter"]').textContent).toBe(
      'Categoría',
    );
    category.value = 'pothole';
    status.value = 'verified';
    category.dispatchEvent(new window.Event('change'));
    expect(onFiltersChange).toHaveBeenCalledWith({
      category: 'pothole',
      status: 'verified',
      resolution: '',
    });
  });

  it('renders loading, empty, error and retry states', () => {
    const { root, store, onRetry } = setup();
    store.startLoading();
    expect(root.getAttribute('aria-busy')).toBe('true');
    expect(root.textContent).toContain('Cargando reportes');
    store.setReports({ items: [], total: 0 });
    expect(root.textContent).toContain('No hay reportes');
    store.setError({ code: 'bad', message: '<img src=x onerror=alert(1)>' });
    expect(root.querySelector('[role="alert"]').textContent).toContain('<img');
    expect(root.querySelector('img')).toBeNull();
    [...root.querySelectorAll('button')]
      .find((button) => button.textContent === 'Volver a intentar')
      .click();
    expect(onRetry).toHaveBeenCalledOnce();
  });

  it('renders reports, visibly identifies stub verification, selects and retains keyboard focus', () => {
    const { root, store, onSelect } = setup();
    store.setReports({ items: [report()], total: 501 });
    expect(root.textContent).toContain('1 de 501 reportes');
    expect(root.textContent).toContain('Página 1 de 21');
    expect(root.textContent).toContain('Verificado (prueba)');
    const button = root.querySelector('.report-button');
    button.focus();
    button.click();
    expect(onSelect).toHaveBeenCalledWith(report().id);
    store.selectReport(report().id);
    expect(document.activeElement).toBe(button);
    expect(button.getAttribute('aria-pressed')).toBe('true');
  });
});

describe('list layout', () => {
  it('shows the reference filters first and the rest in a disclosure', () => {
    const { root } = setup();
    const main = [...root.querySelectorAll('.filters-main label')].map(
      (node) => node.textContent,
    );
    expect(main).toEqual([
      'Estado',
      'Categoría',
      'Ordenar',
      'Incluir reportes antiguos',
    ]);
    expect(
      root.querySelector(
        '.filters-more #state-filter, .filters-more #status-filter',
      ),
    ).not.toBeNull();
  });

  it('prints a range count and a decorative lazy thumbnail per row', () => {
    const { root, store } = setup();
    store.setReports({
      items: [report(), report({ id: '12345678-1234-4234-8234-123456789abd' })],
      total: 86,
    });
    expect(root.querySelector('.result-count').textContent).toBe(
      '1 a 2 de 86 reportes',
    );
    const row = root.querySelector('.report-button');
    expect(row.querySelector('.report-category').textContent).toBe('Bache');
    expect(row.querySelector('.report-date')).not.toBeNull();
    expect(row.querySelector('.state-chip').textContent).toBe('Nuevo');
    const thumb = row.querySelector('img.row-thumbnail');
    expect(thumb.loading).toBe('lazy');
    expect(thumb.alt).toBe('');
    thumb.dispatchEvent(new window.Event('error'));
    expect(row.querySelector('img')).toBeNull();
    expect(row.querySelector('p')).toBeNull();
  });

  it('never creates an image from a hostile photo URL', () => {
    const { root, store } = setup();
    store.setReports({
      items: [report({ photo_url: 'javascript:alert(1)' })],
      total: 1,
    });
    expect(root.querySelector('img')).toBeNull();
  });
});

describe('popup content', () => {
  it('renders API strings as literal text and blocks unsafe image URLs', () => {
    const node = createReportDetails(
      report({
        note: '<script>alert(1)</script>',
        photo_url: 'javascript:alert(1)',
        verification: {
          mode: 'stub',
          passed: true,
          checks: [
            {
              name: '<img src=x>',
              passed: false,
              detail: '<svg onload=alert(1)>',
            },
          ],
        },
      }),
    );
    expect(node.querySelector('script, [onload], img')).toBeNull();
    expect(node.textContent).toContain('<script>alert(1)</script>');
    expect(node.textContent).toContain('no es una verificación real');
    expect(node.textContent).toContain('No superada');
  });

  it('shows captured date, localized checks and a photo with meaningful alternative text', () => {
    const node = createReportDetails(report());
    expect(node.querySelector('img').alt).toContain('Bache');
    expect(node.querySelector('time').dateTime).toBe(report().captured_at);
    expect(node.textContent).toContain('Antigüedad');
    node.querySelector('img').dispatchEvent(new window.Event('error'));
    expect(node.textContent).toContain('Foto no disponible');
  });

  it('handles a pending report without verification', () => {
    expect(
      createReportDetails(report({ status: 'pending', verification: null }))
        .textContent,
    ).toContain('Verificación pendiente');
  });
});
