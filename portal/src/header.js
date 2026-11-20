import { filtersHash } from './filters.js';
import { createStaffHelp } from './help.js';
import { ui, t } from './i18n.js';

/** Slim site header shared by every route. Links keep the current map scope.
 * All text is static copy from i18n.js; nothing from the API is rendered here.
 * @param {HTMLElement} root
 * @param {{onStaff: () => void}} options
 */
export function createSiteHeader(root, { onStaff }) {
  const brand = document.createElement('a');
  brand.className = 'brand';
  brand.href = '#/';
  brand.textContent = t.appName;
  const nav = document.createElement('nav');
  nav.className = 'site-nav';
  nav.id = 'site-navigation';
  nav.setAttribute('aria-label', ui.mainNav);
  const menu = document.createElement('button');
  menu.type = 'button';
  menu.className = 'menu-toggle';
  menu.textContent = 'Menú';
  menu.setAttribute('aria-controls', nav.id);
  menu.setAttribute('aria-expanded', 'false');
  const setMenu = (open) => {
    menu.setAttribute('aria-expanded', String(open));
    root.classList.toggle('nav-open', open);
  };
  menu.addEventListener('click', () =>
    setMenu(menu.getAttribute('aria-expanded') !== 'true'),
  );
  const escape = (event) => {
    if (
      event.key === 'Escape' &&
      menu.getAttribute('aria-expanded') === 'true'
    ) {
      setMenu(false);
      menu.focus();
    }
  };
  root.addEventListener('keydown', escape);
  const links = {};
  for (const [name, text, className] of [
    ['map', ui.navMap, 'map-link'],
    ['triage', ui.navTriage, 'triage-link'],
    ['dashboard', ui.navDashboard, 'dashboard-link'],
  ]) {
    const link = document.createElement('a');
    link.className = className;
    link.textContent = text;
    link.href = '#/';
    links[name] = link;
    nav.append(link);
  }
  const staff = document.createElement('button');
  staff.type = 'button';
  staff.className = 'staff-link';
  staff.textContent = ui.navStaff;
  staff.setAttribute('aria-expanded', 'false');
  staff.setAttribute('aria-controls', 'staff-access');
  const help = createStaffHelp();
  const enterStaff = () => {
    const open = onStaff();
    staff.setAttribute('aria-expanded', String(open ?? true));
    if (open !== false) help.introduce();
  };
  staff.addEventListener('click', enterStaff);
  nav.append(staff, help.button);
  root.replaceChildren(brand, menu, nav, help.guide);
  return {
    setStaffOpen(open) {
      staff.setAttribute('aria-expanded', String(open));
    },
    /** @param {object} scope current filters including bbox */
    update(scope) {
      links.map.href = filtersHash('#/', scope);
      links.triage.href = filtersHash('#/triage', scope);
      links.dashboard.href = filtersHash('#/panel', scope);
    },
    /** @param {string} routeName */
    setRoute(routeName) {
      setMenu(false);
      const current = {
        map: 'map',
        triage: 'triage',
        dashboard: 'dashboard',
      }[routeName];
      for (const [name, link] of Object.entries(links)) {
        if (name === current) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
      }
    },
    destroy() {
      staff.removeEventListener('click', enterStaff);
      root.removeEventListener('keydown', escape);
      root.classList.remove('nav-open');
      root.replaceChildren();
    },
  };
}
