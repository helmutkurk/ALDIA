import { ui } from './i18n.js';

/** Municipality states, independent of the verifier status and v0.1 resolution. */
export const STATE_GROUPS = Object.freeze({
  pendiente_verificacion: 'pending',
  rechazado_verificador: 'closed',
  nuevo: 'open',
  en_revision: 'open',
  programado: 'in_work',
  en_proceso: 'in_work',
  resuelto: 'resolved',
  no_procede: 'closed',
  fuera_de_competencia: 'closed',
  duplicado: 'closed',
  oculto: 'hidden',
});
export const STATES = Object.freeze(Object.keys(STATE_GROUPS));
export const GROUPS = Object.freeze([
  'pending',
  'open',
  'in_work',
  'resolved',
  'closed',
  'hidden',
]);
export const GROUP_COLORS = Object.freeze({
  pending: 'var(--state-pending)',
  open: 'var(--state-open)',
  in_work: 'var(--state-work)',
  resolved: 'var(--state-resolved)',
  closed: 'var(--state-closed)',
  hidden: 'var(--state-closed)',
});
/** Explicit contract edges; earlier active states are also legal backward targets. */
export const TRANSITIONS = Object.freeze(
  Object.fromEntries(
    Object.entries({
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
    }).map(([state, next]) => [
      state,
      Object.freeze(state === 'oculto' ? next : [...next, 'oculto']),
    ]),
  ),
);

/** Legacy reports remain usable while the additive API is rolled out. @param {object} report */
export function reportState(report) {
  return (
    report.state ??
    (report.status === 'pending'
      ? 'pendiente_verificacion'
      : report.status === 'rejected'
        ? 'rechazado_verificador'
        : report.resolution === 'fixed'
          ? 'resuelto'
          : report.resolution === 'acknowledged'
            ? 'en_proceso'
            : 'nuevo')
  );
}
/** @param {string} state */
export function stateLabel(state) {
  return ui.states[state] ?? state;
}
/** Infer the restore target from the latest hide event; never guess it. @param {object} report */
export function previousState(report) {
  return [...(report.events ?? [])]
    .reverse()
    .find((e) => e.to_state === 'oculto' && e.from_state !== 'oculto')
    ?.from_state;
}
/** The API is authoritative for roles; the role here controls the offered UI only.
 * @param {object} report @param {'operator'|'supervisor'|'admin'|null} role
 */
export function legalNextStates(report, role) {
  if (!['operator', 'supervisor', 'admin'].includes(role)) return [];
  const supervisor = ['supervisor', 'admin'].includes(role);
  const state = reportState(report);
  if (state === 'oculto')
    return supervisor && STATES.includes(previousState(report))
      ? [previousState(report)]
      : [];
  return (TRANSITIONS[state] ?? []).filter(
    (next) =>
      supervisor ||
      (next !== 'oculto' &&
        ![
          'rechazado_verificador',
          'resuelto',
          'no_procede',
          'fuera_de_competencia',
          'duplicado',
        ].includes(state)),
  );
}
/** @param {string} from @param {string} to @returns {'internal'|'either'|null} */
export function noteRequirement(from, to) {
  if (from === 'rechazado_verificador' && to === 'nuevo') return 'internal';
  if (
    ['no_procede', 'fuera_de_competencia'].includes(to) ||
    (['no_procede', 'fuera_de_competencia', 'duplicado'].includes(from) &&
      to === 'en_revision') ||
    (from === 'en_revision' && to === 'en_proceso')
  )
    return 'either';
  return null;
}
