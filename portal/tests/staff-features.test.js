import { afterEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { createApiClient } from '../src/api.js';
import { createStaffSession, createStaffPanel } from '../src/staff.js';
import { createStaffActions } from '../src/actions.js';
import { createTriage } from '../src/triage.js';
import { filtersHash, parseFilters } from '../src/filters.js';
import {
  STATES,
  STATE_GROUPS,
  TRANSITIONS,
  legalNextStates,
  noteRequirement,
  previousState,
  reportState,
} from '../src/states.js';
import { ui } from '../src/i18n.js';
import { report as baseReport } from './fixtures.js';
const report = (overrides = {}) =>
  baseReport({
    ...(overrides.state ? { state_group: STATE_GROUPS[overrides.state] } : {}),
    ...overrides,
  });

const cleanups = [];
const token = 'synthetic-staff-token-for-unit-tests-only';
const flush = async () => {
  for (let i = 0; i < 16; i++) await Promise.resolve();
};
const mount = () => {
  const root = document.createElement('section');
  document.body.append(root);
  return root;
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
function session(role = 'operator') {
  const staff = createStaffSession();
  cleanups.push(() => staff.destroy());
  staff.setToken(token, role);
  return staff;
}
function controls(root, options) {
  const action = createStaffActions(root, options);
  cleanups.push(() => action.destroy());
  return action;
}

afterEach(() => {
  cleanups
    .splice(0)
    .reverse()
    .forEach((cleanup) => cleanup());
  document.body.replaceChildren();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('binding municipal state machine', () => {
  it('matches all 11 states and groups in the contract', () => {
    const contract = readFileSync('../documentation/api-contract.md', 'utf8');
    const table = [
      ...contract.matchAll(/^\| `([a-z_]+)` \| `([a-z_]+)` \|/gm),
    ].map((match) => [match[1], match[2]]);
    expect(Object.entries(STATE_GROUPS)).toEqual(table);
    expect(STATES).toHaveLength(11);
  });
  it('exposes exactly the documented edges, backward active moves and supervisor moderation', () => {
    const expected = {
      pendiente_verificacion: [],
      rechazado_verificador: ['nuevo'],
      nuevo: ['en_revision'],
      en_revision: [
        'nuevo',
        'programado',
        'en_proceso',
        'no_procede',
        'fuera_de_competencia',
        'duplicado',
      ],
      programado: ['nuevo', 'en_revision', 'en_proceso', 'no_procede'],
      en_proceso: ['nuevo', 'en_revision', 'programado', 'resuelto'],
      resuelto: ['en_revision'],
      no_procede: ['en_revision'],
      fuera_de_competencia: ['en_revision'],
      duplicado: ['en_revision'],
      oculto: [],
    };
    for (const [state, targets] of Object.entries(expected)) {
      expect(TRANSITIONS[state]).toEqual(
        state === 'oculto' ? targets : [...targets, 'oculto'],
      );
      expect(legalNextStates({ state }, null)).toEqual([]);
      expect(legalNextStates({ state }, 'supervisor')).toEqual(
        state === 'oculto' ? [] : [...targets, 'oculto'],
      );
    }
    expect(legalNextStates({ state: 'nuevo' }, 'operator')).toEqual([
      'en_revision',
    ]);
    expect(
      legalNextStates({ state: 'rechazado_verificador' }, 'operator'),
    ).toEqual([]);
    expect(legalNextStates({ state: 'resuelto' }, 'operator')).toEqual([]);
    expect(legalNextStates({ state: 'duplicado' }, 'operator')).toEqual([]);
  });
  it('restores only the previous hidden state and requires notes at exact contract edges', () => {
    const hidden = {
      state: 'oculto',
      events: [
        { from_state: 'nuevo', to_state: 'oculto' },
        { from_state: 'oculto', to_state: 'nuevo' },
        { from_state: 'en_proceso', to_state: 'oculto' },
      ],
    };
    expect(previousState(hidden)).toBe('en_proceso');
    expect(legalNextStates(hidden, 'supervisor')).toEqual(['en_proceso']);
    expect(legalNextStates(hidden, 'operator')).toEqual([]);
    expect(noteRequirement('rechazado_verificador', 'nuevo')).toBe('internal');
    for (const [from, to] of [
      ['en_revision', 'no_procede'],
      ['programado', 'no_procede'],
      ['en_revision', 'fuera_de_competencia'],
      ['en_revision', 'en_proceso'],
      ['duplicado', 'en_revision'],
      ['no_procede', 'en_revision'],
      ['fuera_de_competencia', 'en_revision'],
    ])
      expect(noteRequirement(from, to)).toBe('either');
    for (const [from, to] of [
      ['en_revision', 'duplicado'],
      ['nuevo', 'en_revision'],
      ['en_proceso', 'resuelto'],
      ['programado', 'nuevo'],
    ])
      expect(noteRequirement(from, to)).toBeNull();
    expect(reportState(report())).toBe('nuevo');
    expect(reportState(report({ status: 'pending', verification: null }))).toBe(
      'pendiente_verificacion',
    );
  });
});

describe('memory-only staff mode', () => {
  it('never writes storage or navigation, clears on pagehide and a fresh session starts public', () => {
    const persist = vi.spyOn(window.Storage.prototype, 'setItem');
    const originalHash = window.location.hash;
    const staff = session();
    expect(staff.getToken()).toBe(token);
    expect(staff.getRole()).toBe('operator');
    const fresh = createStaffSession();
    cleanups.push(() => fresh.destroy());
    expect(fresh.getToken()).toBe('');
    expect(fresh.getRole()).toBeNull();
    window.dispatchEvent(new window.Event('pagehide'));
    expect(staff.getToken()).toBe('');
    expect(staff.getRole()).toBeNull();
    expect(persist).not.toHaveBeenCalled();
    expect(window.location.hash).toBe(originalHash);
  });
  it('uses an explicitly enabled development panel, rejects short tokens and removes the input value after activation', async () => {
    const staff = createStaffSession();
    cleanups.push(() => staff.destroy());
    const root = mount();
    const panel = createStaffPanel(root, staff, {
      getAuthConfig: async () => ({ enabled: true, dev_tokens: true }),
      getMe: async () => {
        throw { status: 401 };
      },
    });
    cleanups.push(() => panel.destroy());
    await panel.ready;
    const input = root.querySelector('#staff-token');
    expect(input.type).toBe('password');
    expect(input.autocomplete).toBe('off');
    input.value = 'too-short';
    submit(root.querySelector('.dev-token-form'));
    expect(staff.getToken()).toBe('');
    expect(root.textContent).toContain(ui.tokenLength);
    input.value = token;
    submit(root.querySelector('.dev-token-form'));
    expect(staff.getToken()).toBe(token);
    expect(input.value).toBe('');
    expect(root.querySelector('form').hidden).toBe(true);
    expect(root.textContent).not.toContain(token);
    root.querySelector('.logout-button').click();
    expect(staff.getToken()).toBe('');
  });
  it('sends staff credentials only as a header and removes it from subsequent public fetches', async () => {
    vi.useFakeTimers();
    const staff = session();
    const fetchImpl = vi.fn(async () =>
      json({ items: [], total: 0, limit: 25, offset: 0 }),
    );
    const api = createApiClient({ staff, fetchImpl });
    await api.getReports({});
    expect(fetchImpl.mock.calls[0][1].headers['X-Staff-Token']).toBe(token);
    expect(fetchImpl.mock.calls[0][0]).not.toContain(token);
    expect(fetchImpl.mock.calls[0][1].cache).toBe('no-store');
    staff.clear();
    await api.getReports({});
    expect(fetchImpl.mock.calls[1][1].headers).not.toHaveProperty(
      'X-Staff-Token',
    );
    expect(vi.getTimerCount()).toBe(0);
  });
});

describe('transition and assignment forms with mocked fetch', () => {
  it('renders no staff controls for public viewers and only legal options for operators', () => {
    const root = mount();
    controls(root, {
      report: report({ state: 'nuevo' }),
      api: {},
      staff: { getToken: () => '' },
    });
    expect(root.querySelector('form')).toBeNull();
    controls(root, {
      report: report({ state: 'nuevo' }),
      api: {},
      staff: session(),
    });
    expect(
      [...root.querySelector('[name="to"]').options].map(
        (option) => option.value,
      ),
    ).toEqual(['en_revision']);
  });
  it('blocks closing and forward skips without a reason, then sends the public note literally', async () => {
    vi.useFakeTimers();
    const staff = session();
    const root = mount();
    const fetchImpl = vi.fn(async () => json(report({ state: 'no_procede' })));
    const api = createApiClient({ staff, fetchImpl });
    const saved = vi.fn();
    controls(root, {
      report: report({ state: 'en_revision' }),
      api,
      staff,
      onSaved: saved,
    });
    const form = root.querySelector('.transition-form');
    const next = form.querySelector('select');
    for (const target of ['no_procede', 'fuera_de_competencia', 'en_proceso']) {
      next.value = target;
      next.dispatchEvent(new window.Event('change'));
      submit(form);
      expect(root.textContent).toContain(ui.reasonRequired);
    }
    expect(fetchImpl).not.toHaveBeenCalled();
    next.value = 'no_procede';
    const hostile = '<img src=x onerror=alert(1)>';
    form.querySelector('[name="public_note"]').value = hostile;
    submit(form);
    await flush();
    expect(new URL(fetchImpl.mock.calls[0][0]).pathname).toMatch(
      /\/transition$/,
    );
    expect(fetchImpl.mock.calls[0][1].method).toBe('POST');
    expect(JSON.parse(fetchImpl.mock.calls[0][1].body)).toEqual({
      to: 'no_procede',
      public_note: hostile,
    });
    expect(saved).toHaveBeenCalledTimes(1);
    expect(root.querySelector('img')).toBeNull();
  });
  it('requires an internal note for supervisor verifier override, public notes alone do not suffice', async () => {
    const staff = session('supervisor');
    const root = mount();
    const fetchImpl = vi.fn(async () => json(report({ state: 'nuevo' })));
    const api = createApiClient({ staff, fetchImpl });
    controls(root, {
      report: report({ state: 'rechazado_verificador' }),
      api,
      staff,
    });
    const form = root.querySelector('.transition-form');
    form.querySelector('[name="to"]').value = 'nuevo';
    form.querySelector('[name="public_note"]').value = 'Revisado';
    submit(form);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(root.textContent).toContain(ui.internalRequired);
    form.querySelector('[name="internal_note"]').value =
      'Comprobación manual de la foto';
    submit(form);
    await flush();
    expect(JSON.parse(fetchImpl.mock.calls[0][1].body).internal_note).toBe(
      'Comprobación manual de la foto',
    );
  });
  it('validates duplicate master UUID and supports clearing assignment to null', async () => {
    const staff = session();
    const root = mount();
    const fetchImpl = vi.fn(async () => json(report({ state: 'duplicado' })));
    const api = createApiClient({ staff, fetchImpl });
    controls(root, { report: report({ state: 'en_revision' }), api, staff });
    const form = root.querySelector('.transition-form');
    const next = form.querySelector('[name="to"]');
    next.value = 'duplicado';
    next.dispatchEvent(new window.Event('change'));
    const master = form.querySelector('[name="duplicate_of"]');
    for (const id of ['invalid', report().id]) {
      master.value = id;
      submit(form);
    }
    expect(fetchImpl).not.toHaveBeenCalled();
    const id = '22345678-1234-4234-8234-123456789abc';
    master.value = id;
    submit(form);
    await flush();
    expect(JSON.parse(fetchImpl.mock.calls[0][1].body)).toEqual({
      to: 'duplicado',
      duplicate_of: id,
    });
    submit(root.querySelector('.assignment-form'));
    await flush();
    expect(JSON.parse(fetchImpl.mock.calls[1][1].body)).toEqual({
      assignee: null,
    });
    expect(new URL(fetchImpl.mock.calls[1][0]).pathname).toMatch(/\/assign$/);
  });
  it.each([
    [409, ui.conflict],
    [401, ui.unauthorized],
    [503, ui.unavailable],
  ])(
    'explains HTTP %i in Spanish without interpreting hostile API errors',
    async (status, expected) => {
      const staff = session();
      const root = mount();
      const fetchImpl = vi.fn(async () =>
        json(
          { error: { code: 'test', message: '<script>bad()</script>' } },
          status,
        ),
      );
      const api = createApiClient({ staff, fetchImpl });
      controls(root, { report: report({ state: 'nuevo' }), api, staff });
      submit(root.querySelector('.transition-form'));
      await flush();
      expect(root.textContent).toContain(expected);
      expect(root.querySelector('script')).toBeNull();
      expect(root.querySelector('button[type="submit"]').disabled).toBe(false);
    },
  );
});

describe('queue tabs and pagination', () => {
  it('offers no write controls or queue fetch without a staff token', async () => {
    const root = mount();
    const fetchImpl = vi.fn();
    const page = createTriage(root, {
      api: createApiClient({ fetchImpl }),
      staff: { getToken: () => '' },
    });
    cleanups.push(() => page.destroy());
    await flush();
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(root.textContent).toContain(ui.staffNeeded);
    expect(root.querySelector('form')).toBeNull();
  });
  it('loads review oldest-first queue, exposes age and switches tabs by keyboard for supervisor override', async () => {
    vi.useFakeTimers();
    const staff = session('supervisor');
    const root = mount();
    const fetchImpl = vi.fn(async (url) => {
      const rejected = new URL(url).searchParams.get('tab') === 'rejected';
      return json({
        items: [
          report({
            state: rejected ? 'rechazado_verificador' : 'nuevo',
            age_hours: 73,
          }),
        ],
        total: 1,
        limit: 25,
        offset: 0,
      });
    });
    const page = createTriage(root, {
      api: createApiClient({ staff, fetchImpl }),
      staff,
    });
    cleanups.push(() => page.destroy());
    await flush();
    expect(new URL(fetchImpl.mock.calls[0][0]).searchParams.get('tab')).toBe(
      'review',
    );
    expect(root.querySelector('.age-badge').textContent).toBe(ui.age(73));
    const tabs = root.querySelectorAll('[role="tab"]');
    expect(tabs[0].getAttribute('aria-selected')).toBe('true');
    tabs[0].dispatchEvent(
      new window.KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }),
    );
    await flush();
    expect(new URL(fetchImpl.mock.calls[1][0]).searchParams.get('tab')).toBe(
      'rejected',
    );
    expect(tabs[1].getAttribute('aria-selected')).toBe('true');
    expect(document.activeElement).toBe(tabs[1]);
    expect(
      [...root.querySelector('[name="to"]').options].map(
        (option) => option.value,
      ),
    ).toEqual(['nuevo', 'oculto']);
    expect(root.querySelector('[name="internal_note"]').required).toBe(true);
    submit(root.querySelector('.transition-form'));
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(root.textContent).toContain(ui.internalRequired);
  });
  it('paginates in batches of 25 and ignores a late response from the previous tab', async () => {
    const staff = session();
    const root = mount();
    let resolveOld;
    const fetchImpl = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveOld = resolve;
          }),
      )
      .mockImplementation(async () =>
        json({ items: [], total: 51, limit: 25, offset: 0 }),
      );
    const page = createTriage(root, {
      api: createApiClient({ staff, fetchImpl }),
      staff,
    });
    cleanups.push(() => page.destroy());
    root.querySelector('#queue-rejected').click();
    await flush();
    resolveOld(json({ items: [report({ state: 'nuevo' })], total: 1 }));
    await flush();
    expect(root.querySelectorAll('.queue-list li')).toHaveLength(0);
    const next = [...root.querySelectorAll('button')].find(
      (button) => button.textContent === ui.next,
    );
    next.click();
    await flush();
    const query = new URL(fetchImpl.mock.calls[2][0]).searchParams;
    expect(query.get('offset')).toBe('25');
    expect(query.get('limit')).toBe('25');
    expect(query.get('tab')).toBe('rejected');
  });
});

describe('shareable contract filters', () => {
  it('round trips all filter dimensions without serializing credentials or private fields', () => {
    const filters = {
      bbox: [-91, 14, -90, 15],
      category: 'pothole',
      state_group: 'open',
      state: 'en_revision',
      created_from: '2026-11-01',
      created_to: '2026-11-19',
      assignee: 'Cuadrilla A & B',
      sort: 'age_in_state',
      include_old: 'true',
    };
    const hash = filtersHash('#/panel', {
      ...filters,
      token,
      internal_note: 'private',
    });
    expect(hash).not.toContain(token);
    expect(hash).not.toContain('private');
    expect(parseFilters(hash)).toEqual(filters);
  });
  it('drops invalid states, sorts, dates, bounding boxes and arbitrary token parameters', () => {
    expect(
      parseFilters(
        '#/?state=script&state_group=invalid&sort=random&bbox=1,2,3&created_from=bad&token=secret',
      ),
    ).toEqual({});
    expect(parseFilters('#/?include_old=false&category=unknown')).toEqual({});
    expect(parseFilters('#/?assignee=' + 'a'.repeat(61))).toEqual({});
  });
});
