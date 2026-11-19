import { element } from './panel.js';
import { ui } from './i18n.js';

/** A tab-local secret, never persisted, serialized, or exposed in navigation. */
export function createStaffSession() {
  let token = '';
  let role = null;
  const listeners = new Set();
  const clear = () => {
    token = '';
    role = null;
    listeners.forEach((fn) => fn());
  };
  window.addEventListener('pagehide', clear);
  return {
    getToken: () => token,
    getRole: () => role,
    /** @param {string} value @param {'operator'|'supervisor'} [requestedRole] */
    setToken(value, requestedRole = 'operator') {
      if (value.trim().length < 32) throw new RangeError(ui.tokenLength);
      token = value.trim();
      role = requestedRole === 'supervisor' ? 'supervisor' : 'operator';
      listeners.forEach((fn) => fn());
    },
    clear,
    /** @param {() => void} fn */
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
/** @param {HTMLElement} root @param {ReturnType<typeof createStaffSession>} session */
export function createStaffPanel(root, session) {
  const heading = element('summary', '', ui.staff);
  const details = element('details', 'staff-panel');
  const form = element('form');
  form.autocomplete = 'off';
  const label = element('label', '', ui.token);
  const input = element('input');
  input.type = 'password';
  input.id = 'staff-token';
  input.autocomplete = 'off';
  input.minLength = 32;
  input.required = true;
  label.htmlFor = input.id;
  const roleLabel = element('label', '', ui.role);
  const role = element('select');
  role.id = 'staff-role';
  roleLabel.htmlFor = role.id;
  for (const id of ['operator', 'supervisor']) {
    const option = element('option', '', ui[id]);
    option.value = id;
    role.append(option);
  }
  const submit = element('button', '', ui.enable);
  submit.type = 'submit';
  const exit = element('button', '', ui.disable);
  exit.type = 'button';
  const status = element('p');
  status.setAttribute('role', 'status');
  form.append(
    label,
    input,
    roleLabel,
    role,
    element('p', 'muted', ui.roleHelp),
    submit,
  );
  details.append(
    heading,
    element('p', 'muted', ui.staffHelp),
    form,
    exit,
    status,
  );
  root.replaceChildren(details);
  const render = () => {
    form.hidden = Boolean(session.getToken());
    exit.hidden = !session.getToken();
    input.value = '';
    status.textContent = session.getToken() ? ui.staffActive : ui.publicMode;
  };
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    try {
      session.setToken(input.value, role.value);
    } catch (error) {
      status.textContent = error.message;
    }
  });
  exit.addEventListener('click', session.clear);
  const unsubscribe = session.subscribe(render);
  render();
  return {
    destroy() {
      unsubscribe();
      root.replaceChildren();
    },
  };
}
