import { readFileSync } from 'node:fs';
import { afterEach, expect, it, vi } from 'vitest';
import { createSiteHeader } from '../src/header.js';
import { createPanel } from '../src/panel.js';

const css = (name) => readFileSync(`src/styles/${name}.css`, 'utf8');
const rule = (source, selector) => {
  const start = source.indexOf(`${selector} {`);
  expect(start, selector).toBeGreaterThanOrEqual(0);
  return source.slice(start, source.indexOf('}', start) + 1);
};
let view;
afterEach(() => {
  view?.destroy();
  document.body.replaceChildren();
});

it('keeps interactive focus-visible rings and suppresses focus outlines on route headings', () => {
  const source = css('base');
  expect(rule(source, ':focus-visible')).toContain(
    'outline: 2px solid var(--focus)',
  );
  expect(rule(source, "h1[tabindex='-1']:focus")).toContain('outline: none');
  expect(rule(source, ':focus:not(:focus-visible)')).toContain('outline: none');
});

it('reserves square thumbnails, two note lines, selection and large touch targets', () => {
  const source = css('workspace');
  const thumb = rule(source, '.row-thumbnail');
  for (const property of [
    'width: 72px',
    'height: 72px',
    'object-fit: cover',
    'background: var(--background)',
    'border-radius:',
  ])
    expect(thumb).toContain(property);
  expect(rule(source, '.thumb-missing')).not.toContain('display: none');
  expect(rule(source, '.report-snippet')).toContain('-webkit-line-clamp: 2');
  expect(rule(source, ".report-button[aria-pressed='true']")).toContain(
    'var(--accent)',
  );
  expect(rule(source, '.report-button:hover')).toContain('background:');
  expect(rule(source, '.report-list .detail-link')).toContain(
    'min-height: 44px',
  );
  expect(rule(source, '.report-button')).toContain('min-height: 96px');
  expect(rule(css('map'), '.search-hint summary')).toContain('width: 44px');
});

it('defines a 1100px twelve-column dashboard with cards and mobile/tablet boundaries', () => {
  const source = css('dashboard');
  expect(rule(source, '.dash-body')).toContain('max-width: 1100px');
  expect(rule(source, '.dash-body')).toContain('repeat(12, minmax(0, 1fr))');
  expect(rule(source, '.dash-block')).toContain(
    'border: 1px solid var(--border)',
  );
  const responsive = css('responsive');
  expect(responsive).toContain('@media (max-width: 700px)');
  expect(responsive).toContain(
    '@media (min-width: 701px) and (max-width: 1000px)',
  );
  expect(rule(responsive, '.map-toggle')).toContain('position: sticky');
  expect(rule(responsive, '.filter-sheet')).toContain('bottom: 0');
  expect(rule(responsive, '.site-nav')).toContain('display: none');
});

it('opens and dismisses the mobile menu, including Escape and route changes', () => {
  const root = document.createElement('header');
  document.body.append(root);
  view = createSiteHeader(root, { onStaff: vi.fn() });
  const menu = root.querySelector('.menu-toggle');
  expect(menu.getAttribute('aria-expanded')).toBe('false');
  expect(menu.getAttribute('aria-controls')).toBe(root.querySelector('nav').id);
  menu.click();
  expect(menu.getAttribute('aria-expanded')).toBe('true');
  root.dispatchEvent(
    new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }),
  );
  expect(menu.getAttribute('aria-expanded')).toBe('false');
  expect(document.activeElement).toBe(menu);
  menu.click();
  view.setRoute('dashboard');
  expect(menu.getAttribute('aria-expanded')).toBe('false');
});

it('opens filters in a modal sheet, preserves values and restores focus on close', () => {
  const root = document.createElement('aside');
  document.body.append(root);
  view = createPanel(root, {
    onSelect: vi.fn(),
    onFiltersChange: vi.fn(),
    onRetry: vi.fn(),
  });
  const dialog = root.querySelector('.filter-sheet');
  dialog.showModal = () => {
    dialog.open = true;
  };
  dialog.close = () => {
    dialog.open = false;
    dialog.dispatchEvent(new window.Event('close'));
  };
  const button = root.querySelector('.filters-toggle');
  button.click();
  expect(dialog.open).toBe(true);
  expect(dialog.getAttribute('aria-labelledby')).toBe(
    dialog.querySelector('h2').id,
  );
  expect(dialog.querySelector('.filters')).not.toBeNull();
  dialog.querySelector('#category-filter').value = 'pothole';
  dialog.querySelector('.filters-done').click();
  expect(dialog.open).toBe(false);
  expect(root.querySelector('.filters-home #category-filter').value).toBe(
    'pothole',
  );
  expect(document.activeElement).toBe(button);
});
