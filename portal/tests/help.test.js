import { afterEach, expect, it, vi } from 'vitest';
import { createSiteHeader } from '../src/header.js';

let header;
afterEach(() => {
  header?.destroy();
  document.body.replaceChildren();
  vi.restoreAllMocks();
});
it('offers keyboard guidance, dismisses it and introduces staff only once without persistent storage', () => {
  const local = vi.spyOn(window.Storage.prototype, 'setItem');
  const root = document.createElement('header');
  document.body.append(root);
  const onStaff = vi.fn();
  header = createSiteHeader(root, { onStaff });
  const help = root.querySelector('.help-button');
  const guide = root.querySelector('.staff-guide');
  expect(guide.hidden).toBe(true);
  root.querySelector('.staff-link').click();
  expect(onStaff).toHaveBeenCalledOnce();
  expect(guide.hidden).toBe(false);
  guide.querySelector('button').click();
  expect(guide.hidden).toBe(true);
  expect(document.activeElement).toBe(help);
  root.querySelector('.staff-link').click();
  expect(guide.hidden).toBe(true);
  help.click();
  expect(document.activeElement.id).toBe('staff-guide-title');
  guide.dispatchEvent(
    new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }),
  );
  expect(help.getAttribute('aria-expanded')).toBe('false');
  expect(document.activeElement).toBe(help);
  expect(local).not.toHaveBeenCalled();
});
