import { filtersHash } from './filters.js';
import { ui, t } from './i18n.js';

/** Slim site header shared by every route. Links keep the current map scope.
 * All text is static copy from i18n.js; nothing from the API is rendered here.
 * @param {HTMLElement} root
 * @param {{onStaff: () => void, onLogout?: () => void}} options
 */
export function createSiteHeader(root, { onStaff, onLogout = () => {} }) {
  const brand = document.createElement('a');
  brand.className = 'brand';
  brand.href = '#/';
  const brandName = document.createElement('span');
  brandName.className = 'brand-name';
  brandName.textContent = t.appName;
  const brandTagline = document.createElement('span');
  brandTagline.className = 'brand-tagline';
  brandTagline.textContent = ui.brandTagline;
  const brandText = document.createElement('span');
  brandText.className = 'brand-text';
  brandText.append(brandName, brandTagline);
  brand.append(icon('logo'), brandText);
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
    link.append(icon(name), labelSpan(text));
    link.href = '#/';
    links[name] = link;
    nav.append(link);
  }
  // Account block (mockup): who is signed in and "Cerrar sesión", or "Iniciar sesión".
  const account = document.createElement('div');
  account.className = 'account-card';
  const staff = document.createElement('button');
  staff.type = 'button';
  staff.className = 'staff-link';
  staff.append(icon('staff'), labelSpan(ui.login));
  staff.setAttribute('aria-expanded', 'false');
  staff.setAttribute('aria-controls', 'staff-access');
  const enterStaff = () => {
    const open = onStaff();
    staff.setAttribute('aria-expanded', String(open ?? true));
  };
  staff.addEventListener('click', enterStaff);
  const logout = document.createElement('button');
  logout.type = 'button';
  logout.className = 'account-logout';
  logout.textContent = ui.logout;
  logout.addEventListener('click', () => onLogout());
  /** @param {{username: string, role: string}|null} user */
  const renderAccount = (user) => {
    if (!user) {
      account.replaceChildren(staff);
      return;
    }
    const avatar = document.createElement('span');
    avatar.className = 'account-avatar';
    avatar.setAttribute('aria-hidden', 'true');
    avatar.textContent = user.username
      .replace(/^dev:/, '')
      .slice(0, 2)
      .toUpperCase();
    const who = document.createElement('span');
    who.className = 'account-who';
    const name = document.createElement('span');
    name.className = 'account-name';
    name.textContent = user.username;
    const role = document.createElement('span');
    role.className = 'account-role';
    role.textContent = ui[user.role] ?? user.role;
    who.append(name, role);
    account.replaceChildren(avatar, who, logout);
  };
  renderAccount(null);
  const org = document.createElement('div');
  org.className = 'org-card';
  const orgLabel = document.createElement('span');
  orgLabel.className = 'org-label';
  orgLabel.textContent = ui.municipality;
  const orgName = document.createElement('span');
  orgName.className = 'org-name';
  orgName.textContent = t.city;
  org.append(orgLabel, orgName);
  root.replaceChildren(brand, menu, nav, account, org);
  return {
    setStaffOpen(open) {
      staff.setAttribute('aria-expanded', String(open));
    },
    setUser: renderAccount,
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

/** @param {string} text */
function labelSpan(text) {
  const span = document.createElement('span');
  span.className = 'nav-label';
  span.textContent = text;
  return span;
}

const ICON_PATHS = {
  map: ['M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2z', 'M9 4v14M15 6v14'],
  triage: [
    'M22 12h-6l-2 3h-4l-2-3H2',
    'M5.5 5h13l3.5 7v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-6z',
  ],
  dashboard: ['M4 20V10M10 20V4M16 20v-7M22 20H2'],
  staff: [
    'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2',
    'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  ],
};

/** Decorative inline SVG icon (static paths, no API data).
 * @param {'logo' | keyof typeof ICON_PATHS} name
 */
function icon(name) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  if (name === 'logo') {
    svg.setAttribute('viewBox', '0 0 40 40');
    svg.setAttribute('class', 'brand-logo');
    const pin = document.createElementNS(ns, 'path');
    pin.setAttribute(
      'd',
      'M20 3c-7.2 0-13 5.6-13 12.6C7 25 20 37 20 37s13-12 13-21.4C33 8.6 27.2 3 20 3z',
    );
    pin.setAttribute('class', 'brand-logo-pin');
    const check = document.createElementNS(ns, 'path');
    check.setAttribute('d', 'M14 16.5l4.2 4.2L26.5 12');
    check.setAttribute('class', 'brand-logo-check');
    svg.append(pin, check);
    return svg;
  }
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('class', 'nav-icon');
  for (const d of ICON_PATHS[name]) {
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', d);
    svg.append(path);
  }
  return svg;
}
