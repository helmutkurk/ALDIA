import { element } from './panel.js';
import { staffError, ui } from './i18n.js';

/** Account identity is in memory; the browser owns the HttpOnly session cookie.
 * The optional development credential is never persisted or serialized. */
export function createStaffSession() {
  let token = '';
  let user = null;
  const listeners = new Set();
  const notify = (reason) => listeners.forEach((fn) => fn(reason));
  const clear = (reason) => {
    token = '';
    user = null;
    notify(reason);
  };
  window.addEventListener('pagehide', clear);
  return {
    getToken: () => token,
    getUser: () => user,
    getRole: () => user?.role ?? null,
    setUser(value) {
      if (
        !value ||
        typeof value.username !== 'string' ||
        !['operator', 'supervisor', 'admin'].includes(value.role)
      )
        throw new TypeError('Invalid staff identity');
      token = '';
      user = Object.freeze({ username: value.username, role: value.role });
      notify();
    },
    /** Development only; the panel is gated by the API config, permissions by the API. */
    setToken(value, requestedRole = 'operator') {
      if (value.trim().length < 32) throw new RangeError(ui.tokenLength);
      token = value.trim();
      const role = requestedRole === 'supervisor' ? 'supervisor' : 'operator';
      user = Object.freeze({ username: `dev:${role}`, role });
      notify();
    },
    clear,
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    destroy() {
      clear();
      listeners.clear();
      window.removeEventListener('pagehide', clear);
    },
  };
}

/** @param {HTMLElement} root @param {ReturnType<typeof createStaffSession>} session
 * @param {object} api */
export function createStaffPanel(root, session, api = {}) {
  let destroyed = false;
  let busy = false;
  let authEnabled = true;
  const controller = new AbortController();
  const details = element('details', 'staff-panel');
  const form = element('form', 'login-form');
  const field = (id, text, type, autocomplete) => {
    const label = element('label', '', text);
    label.htmlFor = id;
    const input = element('input');
    Object.assign(input, { id, type, autocomplete, required: true });
    return { label, input };
  };
  const username = field('staff-username', ui.username, 'text', 'username');
  username.input.maxLength = 64;
  const password = field(
    'staff-password',
    ui.password,
    'password',
    'current-password',
  );
  password.input.maxLength = 1024;
  const submit = element('button', '', ui.login);
  submit.type = 'submit';
  const exit = element('button', 'logout-button', ui.logout);
  exit.type = 'button';
  const status = element('p');
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  const fallback = element('div', 'dev-auth');
  form.append(
    username.label,
    username.input,
    password.label,
    password.input,
    submit,
  );
  details.append(
    element('summary', '', ui.staff),
    element('p', 'muted', ui.loginHelp),
    form,
    fallback,
    exit,
    status,
  );
  root.replaceChildren(details);

  const render = () => {
    const user = session.getUser();
    form.hidden = !authEnabled || Boolean(user);
    fallback.hidden = Boolean(user);
    exit.hidden = !user;
    submit.disabled = busy;
    exit.disabled = busy;
    form.setAttribute('aria-busy', String(busy));
    password.input.value = '';
    status.textContent = user ? ui.signedIn(user) : ui.publicMode;
  };
  const unsubscribe = session.subscribe((reason) => {
    render();
    if (reason?.status === 401) status.textContent = staffError(reason);
  });
  render();
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy) return;
    const secret = password.input.value;
    password.input.value = '';
    busy = true;
    render();
    try {
      const result = await api.login(username.input.value, secret);
      if (!destroyed) session.setUser(result.user);
    } catch (error) {
      if (!destroyed) status.textContent = staffError(error);
    } finally {
      busy = false;
      submit.disabled = false;
      exit.disabled = false;
      form.setAttribute('aria-busy', 'false');
    }
  });
  exit.addEventListener('click', async () => {
    if (busy) return;
    if (session.getToken()) {
      session.clear();
      return;
    }
    busy = true;
    render();
    try {
      await api.logout();
      if (!destroyed) session.clear();
    } catch (error) {
      if (destroyed) return;
      if (error.status === 401) session.clear();
      else status.textContent = staffError(error);
    } finally {
      busy = false;
      submit.disabled = false;
      exit.disabled = false;
      form.setAttribute('aria-busy', 'false');
    }
  });

  function addDevForm() {
    const dev = element('details');
    const devForm = element('form', 'dev-token-form');
    devForm.autocomplete = 'off';
    const credential = field('staff-token', ui.token, 'password', 'off');
    credential.input.minLength = 32;
    const roleLabel = element('label', '', ui.role);
    roleLabel.htmlFor = 'staff-role';
    const role = element('select');
    role.id = 'staff-role';
    for (const id of ['operator', 'supervisor']) {
      const option = element('option', '', ui[id]);
      option.value = id;
      role.append(option);
    }
    const activate = element('button', '', ui.enable);
    activate.type = 'submit';
    devForm.append(
      credential.label,
      credential.input,
      roleLabel,
      role,
      element('p', 'muted', ui.roleHelp),
      activate,
    );
    dev.append(
      element('summary', '', ui.devTokens),
      element('p', 'muted', ui.staffHelp),
      devForm,
    );
    fallback.append(dev);
    devForm.addEventListener('submit', (event) => {
      event.preventDefault();
      try {
        session.setToken(credential.input.value, role.value);
      } catch (error) {
        status.textContent = error.message;
      } finally {
        credential.input.value = '';
      }
    });
  }
  const ready = (async () => {
    // Custom clients used by embedded views may omit authentication entirely.
    // A missing config never enables the development fallback.
    if (!api.getAuthConfig) return;
    submit.disabled = true;
    status.textContent = ui.authLoading;
    try {
      const config = await api.getAuthConfig({ signal: controller.signal });
      if (destroyed) return;
      authEnabled = config.enabled === true;
      if (config.dev_tokens === true) addDevForm();
      form.hidden = !authEnabled;
      if (authEnabled && api.getMe) {
        try {
          const result = await api.getMe({ signal: controller.signal });
          if (!destroyed) session.setUser(result.user);
        } catch (error) {
          if (error.status !== 401) throw error;
        }
      }
      if (!destroyed) {
        render();
      }
    } catch (error) {
      if (!destroyed) status.textContent = staffError(error);
    } finally {
      if (!destroyed) submit.disabled = false;
    }
  })();
  return {
    ready,
    destroy() {
      destroyed = true;
      controller.abort();
      unsubscribe();
      password.input.value = '';
      root.replaceChildren();
    },
  };
}
