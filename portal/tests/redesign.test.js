import { readFileSync } from 'node:fs';
import { afterEach, expect, it, vi } from 'vitest';
import { createSiteHeader } from '../src/header.js';
import { createMapKpis } from '../src/map-kpis.js';

let header;
afterEach(() => {
  header?.destroy();
  document.body.replaceChildren();
});

const css = (name) => readFileSync(`src/styles/${name}.css`, 'utf8');

it('shows the brand, municipality card and nav labels as text next to decorative icons', () => {
  const root = document.createElement('header');
  document.body.append(root);
  header = createSiteHeader(root, { onStaff: vi.fn() });
  expect(root.querySelector('.brand-name').textContent).toBe('Aldia');
  expect(root.querySelector('.brand-tagline').textContent).toBe(
    'Portal de gobierno',
  );
  expect(root.querySelector('.org-label').textContent).toBe('Municipio');
  const labels = [...root.querySelectorAll('.site-nav .nav-label')].map(
    (span) => span.textContent,
  );
  expect(labels).toEqual(['Mapa', 'Triaje', 'Panel']);
  for (const svg of root.querySelectorAll('.site-header svg')) {
    expect(svg.getAttribute('aria-hidden')).toBe('true');
  }
  expect(root.textContent).not.toContain('Modo personal');
  expect(root.querySelector('.help-button')).toBeNull();
});

it('shows "Iniciar sesión" when signed out and the user with "Cerrar sesión" when signed in', () => {
  const root = document.createElement('header');
  document.body.append(root);
  const onStaff = vi.fn();
  const onLogout = vi.fn();
  header = createSiteHeader(root, { onStaff, onLogout });
  const account = root.querySelector('.account-card');
  expect(account.textContent).toBe('Iniciar sesión');
  account.querySelector('.staff-link').click();
  expect(onStaff).toHaveBeenCalledOnce();
  header.setUser({ username: 'ana.lopez', role: 'operator' });
  expect(account.querySelector('.account-name').textContent).toBe('ana.lopez');
  expect(account.querySelector('.account-role').textContent).toBe('Operador');
  expect(account.querySelector('.account-avatar').textContent).toBe('AN');
  account.querySelector('.account-logout').click();
  expect(onLogout).toHaveBeenCalledOnce();
  header.setUser(null);
  expect(account.querySelector('.staff-link')).not.toBeNull();
});

it('summarizes the map area and blanks values it cannot trust', () => {
  const root = document.createElement('section');
  const kpis = createMapKpis(root);
  kpis.render({
    abiertos: 22,
    resueltos: 26,
    by_state_group: { in_work: 4 },
    resolucion_horas: { median: 216 },
    weekly: [
      { recibidos: 3, resueltos: 1 },
      { recibidos: 5, resueltos: 2 },
    ],
  });
  const values = [...root.querySelectorAll('.map-kpi-value')].map(
    (node) => node.textContent,
  );
  expect(values).toEqual(['22', '4', '26', '9.0 d']);
  expect(root.querySelectorAll('.kpi-spark polyline')).toHaveLength(2);
  kpis.render({ abiertos: '<b>x</b>', resolucion_horas: { median: null } });
  expect(
    [...root.querySelectorAll('.map-kpi-value')].map((n) => n.textContent),
  ).toEqual(['—', '—', '—', '—']);
  kpis.render(null);
  expect(root.querySelector('.map-kpi-value').textContent).toBe('—');
});

it('loads the redesign layer last with the wide-screen layout and the split-screen login', () => {
  const app = css('app').trim().split(/\r?\n/);
  expect(app.at(-1).trim()).toBe("@import './redesign.css';");
  const redesign = css('redesign');
  expect(redesign).toContain('@media (min-width: 1001px)');
  expect(redesign).toContain("'list map'");
  expect(redesign).toContain('.staff-root:has(.login-form:not([hidden]))');
});
