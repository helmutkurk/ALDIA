import { element } from './dom.js';
import {
  legalNextStates,
  noteRequirement,
  reportState,
  stateLabel,
} from './states.js';
import { uuidPattern } from './api.js';
import { ui, staffError } from './i18n.js';

/** Shared, cancellable staff controls for details and triage rows. Server validates roles.
 * @param {HTMLElement} root @param {{report: object, api: object, staff: object, onSaved?: () => void, duplicateOf?: string}} options
 */
export function createStaffActions(
  root,
  { report, api, staff, onSaved = () => {}, duplicateOf = '' },
) {
  if (!(staff?.getRole?.() || staff?.getToken())) return { destroy() {} };
  const controller = new AbortController();
  let alive = true;
  const form = element('form', 'transition-form');
  form.append(element('h3', '', ui.transition));
  const status = element('p');
  status.setAttribute('role', 'status');
  const next = element('select');
  next.name = 'to';
  const targets = legalNextStates(report, staff.getRole());
  for (const id of targets) {
    const option = element('option', '', stateLabel(id));
    option.value = id;
    next.append(option);
  }
  const field = (labelText, input, name) => {
    const label = element('label', '', labelText);
    input.name = name;
    label.append(input);
    form.append(label);
    return input;
  };
  field(ui.nextState, next, 'to');
  const publicNote = field(ui.publicNote, element('textarea'), 'public_note');
  publicNote.maxLength = 280;
  const internalNote = field(
    ui.internalNote,
    element('textarea'),
    'internal_note',
  );
  internalNote.maxLength = 500;
  const duplicate = field(ui.duplicateOf, element('input'), 'duplicate_of');
  duplicate.value = duplicateOf;
  if (duplicateOf && targets.includes('duplicado')) next.value = 'duplicado';
  const hint = element('p', 'muted');
  form.append(hint);
  const submit = element('button', '', ui.save);
  submit.type = 'submit';
  form.append(submit);
  const refreshHint = () => {
    const requirement = noteRequirement(reportState(report), next.value);
    hint.textContent =
      requirement === 'internal'
        ? ui.internalRequired
        : requirement === 'either'
          ? ui.reasonRequired
          : '';
    internalNote.required = requirement === 'internal';
    duplicate.parentElement.hidden = next.value !== 'duplicado';
    duplicate.required = next.value === 'duplicado';
  };
  next.addEventListener('change', refreshHint);
  refreshHint();
  if (!targets.length) {
    form.hidden = true;
    root.append(element('p', 'muted', ui.noTransitions));
  }
  const assignment = element('form', 'assignment-form');
  const assignLabel = element('label', '', ui.assignee);
  const assignee = element('input');
  assignee.name = 'assignee';
  assignee.maxLength = 60;
  assignee.value = report.assignee ?? '';
  assignLabel.append(assignee);
  const assign = element('button', '', ui.assign);
  assign.type = 'submit';
  assignment.append(assignLabel, assign);
  /** @param {() => Promise<unknown>} perform @param {HTMLButtonElement} button */
  async function save(perform, button) {
    button.disabled = true;
    status.textContent = '';
    try {
      await perform();
      if (alive) {
        status.textContent = ui.saved;
        onSaved();
      }
    } catch (error) {
      if (alive && error.name !== 'AbortError')
        status.textContent = staffError(error);
    } finally {
      if (alive) button.disabled = false;
    }
  }
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    if (!legalNextStates(report, staff.getRole()).includes(next.value)) return;
    const requirement = noteRequirement(reportState(report), next.value);
    if (requirement === 'internal' && !internalNote.value.trim()) {
      status.textContent = ui.internalRequired;
      return;
    }
    if (
      requirement === 'either' &&
      !publicNote.value.trim() &&
      !internalNote.value.trim()
    ) {
      status.textContent = ui.reasonRequired;
      return;
    }
    if (
      next.value === 'duplicado' &&
      (!uuidPattern.test(duplicate.value.trim()) ||
        duplicate.value.trim().toLowerCase() === report.id.toLowerCase())
    ) {
      status.textContent = ui.invalidDuplicate;
      return;
    }
    save(
      () =>
        api.transition(
          report.id,
          {
            to: next.value,
            public_note: publicNote.value.trim() || undefined,
            internal_note: internalNote.value.trim() || undefined,
            ...(next.value === 'duplicado'
              ? { duplicate_of: duplicate.value.trim() }
              : {}),
          },
          { signal: controller.signal },
        ),
      submit,
    );
  });
  assignment.addEventListener('submit', (event) => {
    event.preventDefault();
    save(
      () =>
        api.assign(report.id, assignee.value.trim() || null, {
          signal: controller.signal,
        }),
      assign,
    );
  });
  root.append(form, assignment, status);
  return {
    destroy() {
      alive = false;
      controller.abort();
      root.replaceChildren();
    },
  };
}
