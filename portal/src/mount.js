import { GROUPS } from './states.js';
import { ui, t } from './i18n.js';

/** Static map chrome is translated here so UI copy stays in i18n.js. */
export function mountPortal(createPortal) {
  const mapElement = document.querySelector('#map');
  const panelElement = document.querySelector('#panel');
  if (!mapElement || !panelElement) return;
  const region = document.querySelector('#map-region');
  region.setAttribute('aria-labelledby', 'map-title');
  const skip = document.createElement('a');
  skip.className = 'skip-link';
  skip.href = '#reports-list';
  skip.textContent = t.skipToReports;
  skip.addEventListener('click', (event) => {
    event.preventDefault();
    const page = document.querySelector('#page');
    const target =
      page && !page.hidden ? page : document.querySelector('#reports-list');
    if (target) {
      target.tabIndex = -1;
      target.focus();
      target.scrollIntoView?.({ block: 'start' });
    }
  });
  document.body.prepend(skip);
  const title = document.createElement('h2');
  title.id = 'map-title';
  title.className = 'map-title';
  title.textContent = t.city;
  const help = document.createElement('p');
  help.id = 'map-help';
  help.className = 'sr-only';
  help.textContent = t.mapHelp;
  const legend = document.createElement('ul');
  legend.className = 'map-legend';
  for (const status of GROUPS) {
    const item = document.createElement('li');
    const dot = document.createElement('span');
    dot.className = `legend-dot state-pin--${status}`;
    dot.setAttribute('aria-hidden', 'true');
    item.append(dot, document.createTextNode(ui.groups[status]));
    legend.append(item);
  }
  region.append(title, help, legend);
  document.title = `${t.appName} · ${t.portalTitle}`;
  const app = createPortal({
    mapElement,
    panelElement,
    workspaceElement: document.querySelector('#around'),
    pageElement: document.querySelector('#page'),
    headerElement: document.querySelector('#site-header'),
  });
  // Vite HMR should not leave live listeners, timers or a second Leaflet map.
  if (import.meta.hot)
    import.meta.hot.dispose(() => {
      app.destroy();
      skip.remove();
      title.remove();
      help.remove();
      legend.remove();
    });
}
