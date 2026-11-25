import { element } from './dom.js';
import { createStaffActions } from './actions.js';
import { filtersHash } from './filters.js';
import { categoryLabel } from './categories.js';
import { createPhoto } from './photo.js';
import { legalNextStates, noteRequirement, reportState } from './states.js';
import { ui, t, staffError, formatDate } from './i18n.js';

const PAGE = 25;

/** Age badge level: over three days is late, over one day needs attention. */
const ageLevel = (hours) =>
  !Number.isFinite(hours)
    ? 'none'
    : hours >= 72
      ? 'late'
      : hours >= 24
        ? 'warn'
        : 'ok';

/** Verifier verdict shown in the "Verificación" column (dot is decorative). */
function verdict(report) {
  const id =
    report.status === 'verified'
      ? 'verified'
      : report.status === 'rejected'
        ? 'rejected'
        : 'pending';
  const cell = element('span', `queue-verdict queue-verdict--${id}`);
  const dot = element('span', 'queue-dot');
  dot.setAttribute('aria-hidden', 'true');
  cell.append(dot, document.createTextNode(ui.queueVerdict[id]));
  return cell;
}

/** First legal move that needs no note; "Pasar a revisión" when the report is new. */
function quickTarget(report, role) {
  const from = reportState(report);
  const targets = legalNextStates(report, role).filter(
    (to) => to !== 'duplicado' && !noteRequirement(from, to),
  );
  return targets.includes('en_revision') ? 'en_revision' : null;
}

/** Paginated server queue laid out as a table (mockup "Triaje2"); each row reuses the exact
 * detail action rules: assignment inline, every other move under "Más".
 * @param {HTMLElement} root @param {{api: object, staff: object, filters?: object}} options
 */
export function createTriage(
  root,
  { api, staff, filters = {}, onChanged = () => {} },
) {
  let tab = 'review';
  let offset = 0;
  let controller;
  let generation = 0;
  let actions = [];
  root.classList.add('page--triage');
  const head = element('header', 'triage-head');
  const titles = element('div', 'triage-titles');
  const heading = element('h1', '', ui.navTriage);
  heading.tabIndex = -1;
  titles.append(heading, element('p', 'triage-sub', ui.triageSub));
  const tabs = element('div', 'queue-tabs');
  tabs.setAttribute('role', 'tablist');
  tabs.setAttribute('aria-label', ui.triage);
  head.append(titles, tabs);
  const content = element('section', 'triage-card');
  content.id = 'queue-content';
  content.setAttribute('role', 'tabpanel');
  const footnote = element('p', 'triage-foot', ui.triageFoot);
  const counts = { review: null, rejected: null };
  const buttons = ['review', 'rejected'].map((id) => {
    const button = element('button');
    button.type = 'button';
    button.id = `queue-${id}`;
    button.setAttribute('role', 'tab');
    button.setAttribute('aria-controls', content.id);
    button.addEventListener('click', () => {
      tab = id;
      offset = 0;
      load();
    });
    tabs.append(button);
    return button;
  });
  const renderTabs = () =>
    buttons.forEach((button, index) => {
      const id = index === 0 ? 'review' : 'rejected';
      const count = element('span', 'queue-tab-count');
      if (Number.isSafeInteger(counts[id]))
        count.textContent = String(counts[id]);
      button.replaceChildren(document.createTextNode(ui[id]), count);
      const selected = id === tab;
      button.setAttribute('aria-selected', String(selected));
      button.tabIndex = selected ? 0 : -1;
    });
  tabs.addEventListener('keydown', (event) => {
    if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) {
      event.preventDefault();
      const button =
        buttons[
          event.key === 'Home'
            ? 0
            : event.key === 'End'
              ? 1
              : tab === 'review'
                ? 1
                : 0
        ];
      button.click();
      button.focus();
    }
  });

  function row(report, signal, reload) {
    const item = element('li', 'queue-row');
    const photo = createPhoto(report, {
      api,
      signal,
      thumbnail: true,
      quiet: true,
      className: 'queue-photo',
    });
    const info = element('div', 'queue-summary');
    const link = element('a', 'queue-title', categoryLabel(report.category));
    link.href = filtersHash(`#/reports/${report.id}`, filters);
    const meta = element(
      'span',
      'queue-meta',
      report.note
        ? `${formatDate(report.created_at)} · ${report.note}`
        : formatDate(report.created_at),
    );
    info.append(link, meta);
    const age = element('div', 'queue-age');
    age.append(
      element(
        'p',
        `age-badge age-badge--${ageLevel(report.age_hours)}`,
        Number.isFinite(report.age_hours)
          ? ui.age(report.age_hours)
          : t.unknownDate,
      ),
    );
    const assignCell = element('div', 'queue-assign');
    const actionCell = element('div', 'queue-actions');
    const more = element('details', 'queue-more');
    more.append(element('summary', '', ui.queueMore));
    const controls = element('div', 'queue-more-panel');
    more.append(controls);
    const saved = () => {
      onChanged();
      reload();
    };
    actions.push(
      createStaffActions(controls, { report, api, staff, onSaved: saved }),
    );
    // Assignment sits in its own column; the status line stays with the other controls.
    const assignment = controls.querySelector('.assignment-form');
    if (assignment) {
      const input = assignment.querySelector('input');
      if (input) input.placeholder = ui.assignee;
      assignCell.append(assignment);
    }
    const target = quickTarget(report, staff.getRole?.());
    if (target) {
      const quick = element('button', 'queue-quick', ui.queueQuick);
      quick.type = 'button';
      const quickStatus = element('span', 'sr-only');
      quickStatus.setAttribute('role', 'status');
      quick.addEventListener('click', async () => {
        quick.disabled = true;
        try {
          await api.transition(report.id, { to: target }, { signal });
          saved();
        } catch (error) {
          if (error.name === 'AbortError') return;
          quick.disabled = false;
          quickStatus.textContent = staffError(error);
          more.open = true;
          const status = controls.querySelector('[role="status"]');
          if (status) status.textContent = staffError(error);
        }
      });
      actionCell.append(quick, quickStatus);
    }
    actionCell.append(more);
    item.append(photo, info, age, verdict(report), assignCell, actionCell);
    return item;
  }

  async function load() {
    controller?.abort();
    controller = new AbortController();
    const own = controller;
    const current = ++generation;
    actions.forEach((action) => action.destroy());
    actions = [];
    root.replaceChildren(head, content, footnote);
    renderTabs();
    content.setAttribute('aria-labelledby', `queue-${tab}`);
    if (!(staff?.getRole?.() || staff?.getToken())) {
      content.replaceChildren(element('p', 'triage-message', ui.staffNeeded));
      return;
    }
    content.replaceChildren(element('p', 'triage-message', t.loading));
    content.setAttribute('aria-busy', 'true');
    try {
      const page = await api.getQueue(tab, { offset }, { signal: own.signal });
      if (current !== generation) return;
      counts[tab] = page.total;
      renderTabs();
      const columns = element('div', 'queue-columns');
      columns.setAttribute('aria-hidden', 'true');
      for (const name of ui.queueColumns)
        columns.append(element('span', '', name));
      const list = element('ul', 'queue-list');
      for (const report of page.items)
        list.append(row(report, own.signal, load));
      const previous = element('button', '', ui.previous);
      previous.type = 'button';
      previous.disabled = offset === 0;
      previous.addEventListener('click', () => {
        offset -= PAGE;
        load();
      });
      const next = element('button', '', ui.next);
      next.type = 'button';
      next.disabled = offset + PAGE >= page.total;
      next.addEventListener('click', () => {
        offset += PAGE;
        load();
      });
      const pager = element('div', 'queue-pager');
      const range = page.items.length
        ? ui.range(offset + 1, offset + page.items.length, page.total)
        : t.count(0, page.total);
      const buttonsBox = element('span', 'queue-pager-buttons');
      buttonsBox.append(previous, next);
      pager.append(element('span', '', range), buttonsBox);
      content.replaceChildren(
        ...(page.items.length ? [columns, list] : [list]),
      );
      if (!page.items.length)
        content.append(
          element(
            'p',
            'queue-empty',
            tab === 'review' ? ui.queueEmptyReview : ui.queueEmptyRejected,
          ),
        );
      content.append(pager);
    } catch (error) {
      if (current !== generation || error.name === 'AbortError') return;
      const alert = element('p', '', staffError(error));
      alert.setAttribute('role', 'alert');
      const retry = element('button', '', t.retry);
      retry.type = 'button';
      retry.addEventListener('click', load);
      content.replaceChildren(
        element('p', 'triage-message', ui.queueError),
        alert,
        retry,
      );
    } finally {
      if (current === generation) content.setAttribute('aria-busy', 'false');
    }
  }
  load();
  return {
    destroy() {
      generation++;
      controller?.abort();
      actions.forEach((action) => action.destroy());
      root.replaceChildren();
      root.classList.remove('page--triage');
    },
  };
}
