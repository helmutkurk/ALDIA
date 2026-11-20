import { element } from './dom.js';
import { t } from './i18n.js';

/** Move the same controls into a native modal: focus trap and Escape are browser-owned. */
export function mobileFilters(filters) {
  const home = element('div', 'filters-home');
  home.append(filters);
  const button = element('button', 'filters-toggle', t.filters);
  button.type = 'button';
  button.setAttribute('aria-haspopup', 'dialog');
  button.setAttribute('aria-controls', 'mobile-filters');
  const dialog = element('dialog', 'filter-sheet');
  dialog.id = 'mobile-filters';
  dialog.setAttribute('aria-labelledby', 'mobile-filters-title');
  const title = element('h2', '', t.filters);
  title.id = 'mobile-filters-title';
  const done = element('button', 'filters-done', 'Ver reportes');
  done.type = 'button';
  dialog.append(title, done);
  button.addEventListener('click', () => {
    done.before(filters);
    dialog.showModal();
  });
  done.addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => {
    home.append(filters);
    if (mobile?.matches !== false) button.focus({ preventScroll: true });
  });
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) {
      const rect = dialog.getBoundingClientRect();
      if (
        event.clientY < rect.top ||
        event.clientX < rect.left ||
        event.clientX > rect.right
      )
        dialog.close();
    }
  });
  const mobile = window.matchMedia?.('(max-width: 700px)');
  const resize = () => {
    if (!mobile.matches && dialog.open) dialog.close();
  };
  mobile?.addEventListener('change', resize);
  return {
    nodes: [button, home, dialog],
    destroy() {
      mobile?.removeEventListener('change', resize);
      if (dialog.open) dialog.close();
    },
  };
}
