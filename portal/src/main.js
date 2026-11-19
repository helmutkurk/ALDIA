import 'leaflet/dist/leaflet.css';
import './styles/tokens.css';
import './styles/app.css';
import { ApiError, createApiClient } from './api.js';
import { createReportMap } from './map.js';
import { createDashboard } from './dashboard.js';
import { createPlaceSearch } from './geocoder.js';
import { createReportPage } from './report.js';
import { createRouter } from './router.js';
import { createPanel, element } from './panel.js';
import { createStore, filterReports } from './state.js';
import { STATUSES, t } from './i18n.js';

/**
 * Compose the modules. Factories can be replaced in tests without network or tiles.
 * @param {{mapElement: HTMLElement, panelElement: HTMLElement, api?: ReturnType<typeof createApiClient>, mapFactory?: typeof createReportMap, pageElement?: HTMLElement, workspaceElement?: HTMLElement, locationMapFactory?: typeof import('./map.js').createLocationMap}} options
 */
export function createPortal({
  mapElement,
  panelElement,
  api = createApiClient(),
  mapFactory = createReportMap,
  pageElement,
  workspaceElement,
  locationMapFactory,
}) {
  const store = createStore();
  let timer;
  let controller;
  let generation = 0;
  let destroyed = false;
  let active = true;
  let needsLoad = true;
  let page;
  let returnFocus;
  function scheduleLoad() {
    if (destroyed) return;
    needsLoad = true;
    if (!active) return;
    clearTimeout(timer);
    controller?.abort();
    const requestGeneration = ++generation;
    store.startLoading();
    timer = setTimeout(async () => {
      controller = new AbortController();
      try {
        const page = await api.getReports(
          { bbox: map.getBbox(), ...store.getState().filters },
          { signal: controller.signal },
        );
        // Aborting is best effort; this guard also rejects late completed responses.
        if (!destroyed && requestGeneration === generation) {
          store.setReports(page);
          needsLoad = false;
        }
      } catch (error) {
        if (destroyed || requestGeneration !== generation) return;
        if (error.name !== 'AbortError')
          store.setError(
            error instanceof ApiError
              ? error.error
              : { code: 'network_error', message: t.networkError },
          );
      }
    }, 300);
  }
  const map = mapFactory(mapElement, {
    onBoundsChange: scheduleLoad,
    onSelect: (id) => store.selectReport(id),
  });
  const panel = createPanel(panelElement, {
    onFiltersChange(filters) {
      store.setFilters(filters);
      scheduleLoad();
    },
    onSelect(id) {
      store.selectReport(id);
      map.focusReport(id);
    },
    onRetry: scheduleLoad,
  });
  const searchRoot = element('div');
  panelElement.querySelector('.panel-header').after(searchRoot);
  const search = createPlaceSearch(searchRoot, {
    onSelect: (place) => map.flyToPlace(place),
  });
  let previousReports;
  let previousFilters;
  const unsubscribe = store.subscribe((state) => {
    panel.render(state);
    if (
      state.reports !== previousReports ||
      state.filters !== previousFilters
    ) {
      map.renderReports(filterReports(state.reports, state.filters));
      previousReports = state.reports;
      previousFilters = state.filters;
    }
  });
  const router =
    pageElement && workspaceElement
      ? createRouter((route) => {
          page?.destroy();
          page = null;
          const wasActive = active;
          active = route.name === 'map';
          if (wasActive && !active) returnFocus = document.activeElement;
          workspaceElement.hidden = !active;
          pageElement.hidden = active;
          if (active) {
            map.invalidateSize?.();
            if (needsLoad) scheduleLoad();
            if (returnFocus?.isConnected)
              returnFocus.focus({ preventScroll: true });
            if (window.location.hash === '#reports-list')
              panelElement.querySelector('#reports-list').focus();
          } else {
            clearTimeout(timer);
            controller?.abort();
            generation++;
            search.cancel();
            if (route.name === 'report') {
              page = createReportPage(pageElement, {
                api,
                id: route.id,
                mapFactory: locationMapFactory,
              });
            } else if (route.name === 'dashboard') {
              page = createDashboard(pageElement, {
                api,
                filters: { bbox: map.getBbox(), ...store.getState().filters },
              });
            } else {
              const heading = element('h1', '', t.pageNotFound);
              heading.tabIndex = -1;
              const back = element('a', '', t.backToMap);
              back.href = '#/';
              pageElement.replaceChildren(heading, back);
              heading.focus();
            }
          }
        })
      : null;
  if (!router) scheduleLoad();
  return {
    store,
    router,
    destroy() {
      destroyed = true;
      generation++;
      clearTimeout(timer);
      controller?.abort();
      unsubscribe();
      router?.destroy();
      page?.destroy();
      search.destroy();
      panel.destroy();
      map.destroy();
    },
  };
}

/** Static map chrome is translated here so UI copy stays in i18n.js. */
function mount() {
  const mapElement = document.querySelector('#map');
  const panelElement = document.querySelector('#panel');
  if (!mapElement || !panelElement) return;
  const region = document.querySelector('#map-region');
  region.setAttribute('aria-labelledby', 'map-title');
  const skip = document.createElement('a');
  skip.className = 'skip-link';
  skip.href = '#reports-list';
  skip.textContent = t.skipToReports;
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
  for (const status of STATUSES) {
    const item = document.createElement('li');
    const dot = document.createElement('span');
    dot.className = `legend-dot legend-dot--${status}`;
    dot.setAttribute('aria-hidden', 'true');
    item.append(dot, document.createTextNode(t.statuses[status]));
    legend.append(item);
  }
  region.append(title, help, legend);
  document.title = `${t.appName} · ${t.portalTitle}`;
  const app = createPortal({
    mapElement,
    panelElement,
    workspaceElement: document.querySelector('#around'),
    pageElement: document.querySelector('#page'),
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

mount();
