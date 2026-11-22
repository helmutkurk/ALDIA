import { readFileSync } from 'node:fs';
import { afterEach, expect, it, vi } from 'vitest';
import { createSiteHeader } from '../src/header.js';

let header;
afterEach(() => {
  header?.destroy();
  document.body.replaceChildren();
});

const css = (name) => readFileSync(`src/styles/${name}.css`, 'utf8');

it('shows the brand with its tagline and keeps nav labels as text next to decorative icons', () => {
  const root = document.createElement('header');
  document.body.append(root);
  header = createSiteHeader(root, { onStaff: vi.fn() });
  expect(root.querySelector('.brand-name').textContent).toBe('Aldia');
  expect(root.querySelector('.brand-tagline').textContent).toBe(
    'Portal de gobierno',
  );
  const labels = [...root.querySelectorAll('.site-nav .nav-label')].map(
    (span) => span.textContent,
  );
  expect(labels).toEqual(['Mapa', 'Triaje', 'Panel', 'Modo personal']);
  for (const svg of root.querySelectorAll('.site-nav svg, .brand svg')) {
    expect(svg.getAttribute('aria-hidden')).toBe('true');
  }
});

it('mirrors the shared Guatemala sky-blue tokens and loads the redesign layer last', () => {
  const tokens = css('tokens');
  for (const value of [
    '--primary: #2a6fa8',
    '--brand: #4997d0',
    '--accent: #ff7a59',
    '--state-open: #b26a00',
    '--state-work: #7e57c2',
    '--state-resolved: #17735a',
    '--state-closed: #6b7280',
  ]) {
    expect(tokens).toContain(value);
  }
  const app = css('app').trim().split(/\r?\n/);
  expect(app.at(-1).trim()).toBe("@import './redesign.css';");
  expect(css('redesign')).toContain('@media (min-width: 1001px)');
});
