import { element } from './panel.js';
import { createStaffActions } from './actions.js';
import { filtersHash } from './filters.js';
import { categoryLabel } from './categories.js';
import { reportState, stateLabel } from './states.js';
import { ui, t, staffError } from './i18n.js';

/** Paginated server queue; each row reuses the exact detail action rules.
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
  const back = element('a', '', t.backToMap);
  back.href = filtersHash('#/', filters);
  const heading = element('h1', '', ui.triage);
  heading.tabIndex = -1;
  const tabs = element('div', 'queue-tabs');
  tabs.setAttribute('role', 'tablist');
  tabs.setAttribute('aria-label', ui.triage);
  const content = element('section');
  content.id = 'queue-content';
  content.setAttribute('role', 'tabpanel');
  const buttons = ['review', 'rejected'].map((id) => {
    const button = element('button', '', ui[id]);
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
  async function load() {
    controller?.abort();
    controller = new AbortController();
    const current = ++generation;
    actions.forEach((action) => action.destroy());
    actions = [];
    root.replaceChildren(back, heading, tabs, content);
    buttons.forEach((button, index) => {
      const selected = (index === 0 ? 'review' : 'rejected') === tab;
      button.setAttribute('aria-selected', String(selected));
      button.tabIndex = selected ? 0 : -1;
    });
    content.setAttribute('aria-labelledby', `queue-${tab}`);
    if (!(staff?.getRole?.() || staff?.getToken())) {
      content.replaceChildren(element('p', '', ui.staffNeeded));
      return;
    }
    content.replaceChildren(element('p', '', t.loading));
    content.setAttribute('aria-busy', 'true');
    try {
      const page = await api.getQueue(
        tab,
        { offset },
        { signal: controller.signal },
      );
      if (current !== generation) return;
      const list = element('ul', 'queue-list');
      for (const report of page.items) {
        const row = element('li');
        const link = element('a', '', categoryLabel(report.category));
        link.href = filtersHash(`#/reports/${report.id}`, filters);
        row.append(
          link,
          element('p', '', stateLabel(reportState(report))),
          element(
            'p',
            'age-badge',
            Number.isFinite(report.age_hours)
              ? ui.age(report.age_hours)
              : t.unknownDate,
          ),
        );
        const controls = element('div');
        row.append(controls);
        actions.push(
          createStaffActions(controls, {
            report,
            api,
            staff,
            onSaved: () => {
              onChanged();
              load();
            },
          }),
        );
        list.append(row);
      }
      const previous = element('button', '', ui.previous);
      previous.type = 'button';
      previous.disabled = offset === 0;
      previous.addEventListener('click', () => {
        offset -= 25;
        load();
      });
      const next = element('button', '', ui.next);
      next.type = 'button';
      next.disabled = offset + 25 >= page.total;
      next.addEventListener('click', () => {
        offset += 25;
        load();
      });
      content.replaceChildren(
        element('p', '', t.count(page.items.length, page.total)),
        list,
        previous,
        element('span', '', ui.page(offset / 25 + 1, page.total)),
        next,
      );
      if (!page.items.length) content.append(element('p', '', t.empty));
    } catch (error) {
      if (current !== generation || error.name === 'AbortError') return;
      const alert = element('p', '', staffError(error));
      alert.setAttribute('role', 'alert');
      const retry = element('button', '', t.retry);
      retry.type = 'button';
      retry.addEventListener('click', load);
      content.replaceChildren(element('p', '', ui.queueError), alert, retry);
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
    },
  };
}
