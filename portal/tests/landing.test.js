import { afterEach, expect, it, vi } from 'vitest';
import { createLanding } from '../src/landing.js';
import { createStaffSession } from '../src/staff.js';
import { ui } from '../src/i18n.js';

let landing;
let staff;
afterEach(() => {
  landing?.destroy();
  staff?.destroy();
  document.body.replaceChildren();
  document.body.className = '';
});
const flush = async () => {
  for (let i = 0; i < 6; i++) await Promise.resolve();
};
function setup(api = {}) {
  const header = document.createElement('header');
  const main = document.createElement('main');
  const root = document.createElement('div');
  document.body.append(header, main, root);
  staff = createStaffSession();
  const onClose = vi.fn();
  landing = createLanding(root, { api, staff, onClose, hide: [header, main] });
  return { header, main, root, onClose };
}
const fill = (root, user, secret) => {
  root.querySelector('#landing-username').value = user;
  root.querySelector('#landing-password').value = secret;
  root
    .querySelector('.landing-form')
    .dispatchEvent(new window.Event('submit', { cancelable: true }));
};

it('is the first screen and keeps the portal behind it out of reach', async () => {
  const { header, main, root } = setup();
  await flush();
  expect(root.hidden).toBe(false);
  expect(root.querySelector('h1').textContent).toBe(ui.login);
  expect(root.textContent).toContain(ui.landing.headline);
  expect(root.querySelectorAll('.landing-points li')).toHaveLength(3);
  expect(header.inert).toBe(true);
  expect(main.inert).toBe(true);
  expect(document.body.classList.contains('landing-open')).toBe(true);
  expect(document.activeElement).toBe(root.querySelector('#landing-username'));
  for (const svg of root.querySelectorAll('svg'))
    expect(svg.getAttribute('aria-hidden')).toBe('true');
});

it('continues to the public map without an account', () => {
  const { header, main, root, onClose } = setup();
  root.querySelector('.landing-skip').click();
  expect(root.hidden).toBe(true);
  expect(root.childElementCount).toBe(0);
  expect(header.inert).toBe(false);
  expect(main.inert).toBe(false);
  expect(document.body.classList.contains('landing-open')).toBe(false);
  expect(onClose).toHaveBeenCalledWith('public');
});

it('signs in through the API, clears the password and opens the portal', async () => {
  const api = {
    login: vi.fn().mockResolvedValue({
      user: { username: 'operadora', role: 'operator' },
    }),
  };
  const { root, onClose } = setup(api);
  fill(root, 'operadora', 'not-a-real-secret');
  expect(root.querySelector('#landing-password').value).toBe('');
  await flush();
  expect(api.login).toHaveBeenCalledWith('operadora', 'not-a-real-secret');
  expect(staff.getRole()).toBe('operator');
  expect(root.hidden).toBe(true);
  expect(onClose).toHaveBeenCalledWith('login');
});

it('shows the API error and stays open after a failed or locked login', async () => {
  const error = Object.assign(new Error('locked'), {
    status: 423,
    error: { code: 'account_locked', message: 'locked' },
  });
  const api = { login: vi.fn().mockRejectedValue(error) };
  const { root } = setup(api);
  fill(root, 'operadora', 'wrong');
  await flush();
  expect(root.hidden).toBe(false);
  expect(root.querySelector('.landing-status').textContent).not.toBe('');
  expect(root.querySelector('.landing-submit').disabled).toBe(false);
  expect(staff.getRole()).toBeNull();
});

it('closes by itself when an existing staff session is restored', async () => {
  const { root, onClose } = setup();
  staff.setUser({ username: 'supervisora', role: 'supervisor' });
  await flush();
  expect(root.hidden).toBe(true);
  expect(onClose).toHaveBeenCalledWith('login');
});
