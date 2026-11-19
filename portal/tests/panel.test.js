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
    expect(root.textContent).toContain('500 reportes');
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
