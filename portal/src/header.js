import { filtersHash } from './filters.js';
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
  nav.setAttribute('aria-label', ui.mainNav);
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
  staff.addEventListener('click', onStaff);
  nav.append(staff);
  root.replaceChildren(brand, nav);
  return {
    /** @param {object} scope current filters including bbox */
    update(scope) {
      links.map.href = filtersHash('#/', scope);
      links.triage.href = filtersHash('#/triage', scope);
      links.dashboard.href = filtersHash('#/panel', scope);
    },
    /** @param {string} routeName */
    setRoute(routeName) {
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
      staff.removeEventListener('click', onStaff);
      root.replaceChildren();
    },
  };
}
