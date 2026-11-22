import { element } from './dom.js';
import { staffError, ui } from './i18n.js';

const SVG_NS = 'http://www.w3.org/2000/svg';

/** Decorative SVG from path data; the text next to it carries the meaning.
 * @param {string} viewBox @param {Array<[string, Record<string,string>]>} shapes */
function svg(viewBox, shapes, className) {
  const node = document.createElementNS(SVG_NS, 'svg');
  node.setAttribute('viewBox', viewBox);
  node.setAttribute('aria-hidden', 'true');
  if (className) node.setAttribute('class', className);
  for (const [tag, attrs] of shapes) {
    const shape = document.createElementNS(SVG_NS, tag);
    for (const [name, value] of Object.entries(attrs))
      shape.setAttribute(name, value);
    node.append(shape);
  }
  return node;
}

const logo = () =>
  svg(
    '0 0 40 40',
    [
      [
        'path',
        {
          d: 'M20 3c-7.2 0-13 5.6-13 12.6C7 25 20 37 20 37s13-12 13-21.4C33 8.6 27.2 3 20 3z',
          fill: '#5AA3DB',
        },
      ],
      [
        'path',
        {
          d: 'M14 16.5l4.2 4.2L26.5 12',
          fill: 'none',
          stroke: '#FFFFFF',
          'stroke-width': '3.4',
          'stroke-linecap': 'round',
          'stroke-linejoin': 'round',
        },
      ],
    ],
    'landing-logo',
  );

/** First screen on load: staff sign-in on the right, product summary on the left. Anyone can
 * continue to the public map without an account; a restored or new staff session closes it.
 * @param {HTMLElement} root
 * @param {{api: object, staff: object, onClose?: (reason: 'login'|'public') => void,
 *   hide?: HTMLElement[]}} options
 */
export function createLanding(root, { api, staff, onClose, hide = [] }) {
  let busy = false;
  let open = true;
  root.className = 'landing';
  root.setAttribute('role', 'region');
  root.setAttribute('aria-labelledby', 'landing-title');

  const intro = element('section', 'landing-intro');
  const brand = element('div', 'landing-brand');
  const brandText = element('div', 'landing-brand-text');
  brandText.append(
    element('span', 'landing-brand-name', 'ALDÍA'),
    element('span', 'landing-brand-tagline', ui.brandTagline),
  );
  brand.append(logo(), brandText);
  const pitch = element('div', 'landing-pitch');
  pitch.append(
    element('p', 'landing-headline', ui.landing.headline),
    element('p', 'landing-sub', ui.landing.sub),
  );
  const points = element('ul', 'landing-points');
  for (const text of ui.landing.points) {
    const item = element('li');
    const mark = element('span', 'landing-check');
    mark.append(
      svg('0 0 24 24', [
        [
          'path',
          {
            d: 'M5 12.5l4.5 4.5L19 7.5',
            fill: 'none',
            stroke: 'currentColor',
            'stroke-width': '3',
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
          },
        ],
      ]),
    );
    item.append(mark, document.createTextNode(text));
    points.append(item);
  }
  intro.append(
    brand,
    pitch,
    points,
    element('p', 'landing-foot', ui.landing.footer),
  );

  const side = element('section', 'landing-side');
  const form = element('form', 'landing-form');
  const heading = element('h1', '', ui.login);
  heading.id = 'landing-title';
  heading.tabIndex = -1;
  const head = element('div', 'landing-head');
  head.append(heading, element('p', 'muted', ui.landing.formHelp));
  const field = (id, text, type, autocomplete, maxLength) => {
    const label = element('label', 'landing-field');
    label.htmlFor = id;
    const input = element('input');
    Object.assign(input, { id, type, autocomplete, required: true, maxLength });
    label.append(document.createTextNode(text), input);
    return { label, input };
  };
  const username = field(
    'landing-username',
    ui.username,
    'text',
    'username',
    64,
  );
  const password = field(
    'landing-password',
    ui.password,
    'password',
    'current-password',
    1024,
  );
  const submit = element('button', 'landing-submit', ui.landing.enter);
  submit.type = 'submit';
  const status = element('p', 'landing-status');
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  const note = element('div', 'landing-note');
  note.append(
    svg('0 0 24 24', [
      ['rect', { x: '4', y: '11', width: '16', height: '10', rx: '2' }],
      ['path', { d: 'M8 11V7a4 4 0 0 1 8 0v4' }],
    ]),
    element('span', '', ui.landing.lockNote),
  );
  const skip = element('a', 'landing-skip', ui.landing.publicMap);
  skip.href = window.location.hash || '#/';
  form.append(head, username.label, password.label, submit, status, note, skip);
  side.append(form);
  root.replaceChildren(intro, side);

  const previous = hide.map((node) => node.inert);
  hide.forEach((node) => {
    node.inert = true;
  });
  document.body.classList.add('landing-open');
  Promise.resolve().then(() => {
    if (open) username.input.focus({ preventScroll: true });
  });

  function close(reason) {
    if (!open) return;
    open = false;
    unsubscribe();
    password.input.value = '';
    root.hidden = true;
    root.replaceChildren();
    hide.forEach((node, index) => {
      node.inert = previous[index] ?? false;
    });
    document.body.classList.remove('landing-open');
    onClose?.(reason);
  }
  // A cookie session restored by the staff panel, or a login elsewhere, ends the landing.
  const unsubscribe = staff.subscribe(() => {
    if (staff.getUser?.()) close('login');
  });
  if (staff.getUser?.()) Promise.resolve().then(() => close('login'));

  skip.addEventListener('click', (event) => {
    event.preventDefault();
    close('public');
  });
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy) return;
    const secret = password.input.value;
    password.input.value = '';
    busy = true;
    submit.disabled = true;
    form.setAttribute('aria-busy', 'true');
    status.textContent = '';
    try {
      const result = await api.login(username.input.value, secret);
      if (open) staff.setUser(result.user);
    } catch (error) {
      if (open) status.textContent = staffError(error);
    } finally {
      busy = false;
      submit.disabled = false;
      form.setAttribute('aria-busy', 'false');
    }
  });

  return {
    isOpen: () => open,
    close: () => close('public'),
    destroy() {
      close('public');
    },
  };
}
