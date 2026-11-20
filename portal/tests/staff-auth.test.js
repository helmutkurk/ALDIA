import { afterEach, expect, it, vi } from 'vitest';
import { createStaffPanel, createStaffSession } from '../src/staff.js';
import { createApiClient } from '../src/api.js';
import { legalNextStates } from '../src/states.js';
import { createStaffActions } from '../src/actions.js';
import { staffError, ui } from '../src/i18n.js';
import { municipalReport } from './fixtures.js';

let panel, staff;
const flush = async () => {
  for (let i = 0; i < 20; i++) await Promise.resolve();
};
const submit = (form) =>
  form.dispatchEvent(
    new window.Event('submit', { bubbles: true, cancelable: true }),
  );
const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
const mount = (api) => {
  const root = document.createElement('section');
  document.body.append(root);
  staff = createStaffSession();
  panel = createStaffPanel(root, staff, api);
  return root;
};
afterEach(() => {
  panel?.destroy();
  staff?.destroy();
  panel = staff = null;
  document.body.replaceChildren();
  document.cookie = 'aldia_csrf=; Max-Age=0; Path=/';
  vi.restoreAllMocks();
});

it('logs in with labelled fields, clears the password and uses the server role without storage', async () => {
  const storage = vi.spyOn(window.Storage.prototype, 'setItem');
  const api = {
    getAuthConfig: vi.fn(async () => ({ enabled: true, dev_tokens: false })),
    getMe: vi.fn(async () => {
      throw { status: 401 };
    }),
    login: vi.fn(async () => ({
      user: { username: 'operador', role: 'operator' },
    })),
    logout: vi.fn(async () => null),
  };
  const root = mount(api);
  await flush();
  expect(root.querySelector('#staff-token')).toBeNull();
  expect(root.querySelector('#staff-role')).toBeNull();
  expect(root.querySelector('label[for="staff-username"]')).not.toBeNull();
  const password = root.querySelector('#staff-password');
  expect(password.type).toBe('password');
  root.querySelector('#staff-username').value = 'operador';
  password.value = 'synthetic test password';
  submit(root.querySelector('.login-form'));
  await flush();
  expect(api.login).toHaveBeenCalledWith('operador', 'synthetic test password');
  expect(password.value).toBe('');
  expect(staff.getToken()).toBe('');
  expect(staff.getRole()).toBe('operator');
  expect(root.textContent).toContain('operador');
  expect(storage).not.toHaveBeenCalled();
  root.querySelector('.logout-button').click();
  await flush();
  expect(api.logout).toHaveBeenCalledOnce();
  expect(staff.getRole()).toBeNull();
});

it('restores a cookie session and treats admin as supervisor in case controls', async () => {
  const root = mount({
    getAuthConfig: async () => ({ enabled: true, dev_tokens: false }),
    getMe: async () => ({ user: { username: 'administrator', role: 'admin' } }),
  });
  await flush();
  expect(staff.getRole()).toBe('admin');
  expect(root.querySelector('.login-form').hidden).toBe(true);
  const report = municipalReport({ state: 'rechazado_verificador' });
  expect(legalNextStates(report, 'admin')).toEqual(['nuevo', 'oculto']);
  const controls = document.createElement('div');
  const actions = createStaffActions(controls, { report, staff, api: {} });
  expect(controls.querySelector('.transition-form')).not.toBeNull();
  actions.destroy();
});

it('shows the dev token form only after the API explicitly enables it', async () => {
  const root = mount({
    getAuthConfig: async () => ({ enabled: true, dev_tokens: true }),
    getMe: async () => {
      throw { status: 401 };
    },
  });
  expect(root.querySelector('#staff-token')).toBeNull();
  await flush();
  expect(root.querySelector('#staff-token')).not.toBeNull();
});

it('keeps the dev token form absent if configuration cannot be loaded', async () => {
  const root = mount({
    getAuthConfig: async () => {
      throw { status: 503 };
    },
  });
  await flush();
  expect(root.querySelector('#staff-token')).toBeNull();
  expect(root.textContent).toContain(ui.unavailable);
});

it('keeps the account visible and explains failed logout instead of claiming the session ended', async () => {
  const root = mount({
    getAuthConfig: async () => ({ enabled: true, dev_tokens: false }),
    getMe: async () => ({
      user: { username: 'supervisor', role: 'supervisor' },
    }),
    logout: async () => {
      throw { status: 403 };
    },
  });
  await flush();
  root.querySelector('.logout-button').click();
  await flush();
  expect(staff.getRole()).toBe('supervisor');
  expect(root.textContent).toContain(ui.forbidden);
  expect(root.querySelector('.logout-button').disabled).toBe(false);
});

it('sends the CSRF cookie on case writes and accepts real admin actor history', async () => {
  document.cookie = 'aldia_csrf=synthetic-case-csrf; Path=/';
  staff = createStaffSession();
  staff.setUser({ username: 'administrator', role: 'admin' });
  const report = municipalReport({
    events: [
      {
        at: '2026-11-19T19:00:00Z',
        actor: 'administrator',
        actor_role: 'admin',
        from_state: 'nuevo',
        to_state: 'en_revision',
        public_note: null,
      },
    ],
  });
  const fetchImpl = vi.fn(async () => json(report));
  const api = createApiClient({ staff, fetchImpl });
  await expect(
    api.transition(report.id, { to: 'en_revision' }),
  ).resolves.toEqual(report);
  expect(api.hasStaff()).toBe(true);
  expect(fetchImpl.mock.calls[0][1].headers['X-CSRF-Token']).toBe(
    'synthetic-case-csrf',
  );
  expect(fetchImpl.mock.calls[0][1].headers).not.toHaveProperty(
    'X-Staff-Token',
  );
});

it.each([401, 403, 423])(
  'explains login HTTP %i in Spanish and clears the rejected password',
  async (status) => {
    const root = mount({
      getAuthConfig: async () => ({ enabled: true, dev_tokens: false }),
      getMe: async () => {
        throw { status: 401 };
      },
      login: async () => {
        throw { status };
      },
    });
    await flush();
    root.querySelector('#staff-username').value = 'operador';
    root.querySelector('#staff-password').value = 'synthetic test password';
    submit(root.querySelector('.login-form'));
    await flush();
    expect(root.textContent).toContain(staffError({ status }));
    expect(root.querySelector('#staff-password').value).toBe('');
    expect(staff.getRole()).toBeNull();
  },
);

it('sends cookie credentials and double-submit CSRF on writes, never on reads or login', async () => {
  document.cookie = 'aldia_csrf=synthetic-csrf; Path=/';
  const fetchImpl = vi.fn(async (url) =>
    url.endsWith('/login') || url.endsWith('/me')
      ? json({ user: { username: 'operador', role: 'operator' } })
      : url.endsWith('/config')
        ? json({ enabled: true, dev_tokens: false })
        : new Response(null, { status: 204 }),
  );
  const api = createApiClient({ fetchImpl });
  await api.getAuthConfig();
  await api.getMe();
  await api.login('operador', 'synthetic test password');
  await api.logout();
  for (const [, options] of fetchImpl.mock.calls)
    expect(options.credentials).toBe('include');
  expect(fetchImpl.mock.calls[0][1].headers).not.toHaveProperty('X-CSRF-Token');
  expect(fetchImpl.mock.calls[2][1].headers).not.toHaveProperty('X-CSRF-Token');
  expect(fetchImpl.mock.calls[3][1].headers['X-CSRF-Token']).toBe(
    'synthetic-csrf',
  );
  expect(fetchImpl.mock.calls[3][1].headers).not.toHaveProperty(
    'X-Staff-Token',
  );
  expect(ui.actors.admin).toBe('Administrador');
});

it('clears revoked session controls on 401, preserves the API error and offers login again', async () => {
  staff = createStaffSession();
  staff.setUser({ username: 'supervisor', role: 'supervisor' });
  const root = document.createElement('section');
  document.body.append(root);
  panel = createStaffPanel(root, staff);
  const controller = new AbortController();
  // The portal's identity subscriber cancels its former private view immediately.
  const unsubscribe = staff.subscribe(() => controller.abort());
  const api = createApiClient({
    staff,
    fetchImpl: async () =>
      json(
        { error: { code: 'unauthorized', message: 'Sesión vencida.' } },
        401,
      ),
  });
  await expect(
    api.getQueue('review', {}, { signal: controller.signal }),
  ).rejects.toMatchObject({
    status: 401,
    error: { code: 'unauthorized', message: 'Sesión vencida.' },
  });
  expect(staff.getRole()).toBeNull();
  expect(api.hasStaff()).toBe(false);
  expect(controller.signal.aborted).toBe(true);
  expect(root.querySelector('.login-form').hidden).toBe(false);
  expect(root.querySelector('.logout-button').hidden).toBe(true);
  expect(root.textContent).toContain(ui.unauthorized);
  unsubscribe();
});

it('does not clear a newly signed-in identity when a former session returns a late 401', async () => {
  staff = createStaffSession();
  staff.setUser({ username: 'operador', role: 'operator' });
  let respond;
  const api = createApiClient({
    staff,
    fetchImpl: () =>
      new Promise((resolve) => {
        respond = resolve;
      }),
  });
  const oldRequest = api.getQueue('review', {});
  staff.setUser({ username: 'supervisor', role: 'supervisor' });
  respond(
    json({ error: { code: 'unauthorized', message: 'Sesión vencida.' } }, 401),
  );
  await expect(oldRequest).rejects.toMatchObject({ status: 401 });
  expect(staff.getRole()).toBe('supervisor');
});
