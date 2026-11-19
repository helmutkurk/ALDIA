import 'leaflet/dist/leaflet.css';
import './styles/tokens.css';
import './styles/app.css';
import { ApiError, createApiClient } from './api.js';
import { createReportMap } from './map.js';
import { createDashboard } from './dashboard.js';
import { createPlaceSearch } from './geocoder.js';
import { createReportPage } from './report.js';
import { createRouter, parseRoute } from './router.js';
import { createPanel, createReportDetails, element } from './panel.js';
import { createStore, filterReports } from './state.js';
import { GROUPS } from './states.js';
import { parseFilters, filtersHash } from './filters.js';
import { createStaffSession, createStaffPanel } from './staff.js';
import { createStaffActions } from './actions.js';
import { createTriage } from './triage.js';
import { ui, staffError, t } from './i18n.js';

/** Compose the retained workspace and cancellable pages. Factories avoid tiles in tests.
 * @param {object} options
 */
export function createPortal({
  mapElement,
  panelElement,
  api,
  mapFactory = createReportMap,
  pageElement,
  workspaceElement,
  locationMapFactory,
  staff = createStaffSession(),
}) {
  api ??= createApiClient({ staff });
  const store = createStore();
  const { bbox: initialBounds, ...initial } = parseFilters(
    window.location.hash,
  );
  if (Object.keys(initial).length)
    store.setFilters({ category: '', status: '', resolution: '', ...initial });
  let timer, controller, page, returnFocus, router, sideController, sideActions;
  let generation = 0,
    destroyed = false,
    active = true,
    needsLoad = true,
    applyingRoute = false,
    currentRoute;
  const side = element('section', 'selected-report');
  const staffRoot = element('div', 'staff-root');
  const staffPanel = createStaffPanel(staffRoot, staff);
  const query = () => ({ ...store.getState().filters, bbox: map.getBbox() });
  const syncHash = () => {
    if (pageElement && active && currentRoute === 'map' && !applyingRoute)
      window.history.replaceState(null, '', filtersHash('#/', query()));
  };
  async function showReport(id) {
    sideController?.abort();
    sideActions?.destroy();
    sideController = new AbortController();
    const own = sideController;
    side.replaceChildren(element('p', '', t.reportLoading));
    try {
      const report = await api.getReport(id, { signal: own.signal });
      if (own.signal.aborted) return;
      const close = element('button', '', t.closePopup);
      close.type = 'button';
      close.addEventListener('click', () => {
        own.abort();
        sideActions?.destroy();
        side.replaceChildren();
      });
      const details = createReportDetails(report, { api, signal: own.signal });
      details.querySelector('a.detail-link').href = filtersHash(
        `#/reports/${id}`,
        query(),
      );
      const controls = element('div');
      side.replaceChildren(close, details, controls);
      sideActions = createStaffActions(controls, {
        report,
        api,
        staff,
        onSaved: () => {
          showReport(id);
          scheduleLoad();
        },
      });
      details.querySelector('h2').focus();
    } catch (error) {
      if (!own.signal.aborted)
        side.replaceChildren(element('p', '', staffError(error)));
    }
  }
  async function showCluster(cluster) {
    sideController?.abort();
    sideActions?.destroy();
    sideController = new AbortController();
    const own = sideController;
    const close = element('button', '', t.closePopup);
    close.type = 'button';
    close.addEventListener('click', () => {
      own.abort();
      side.replaceChildren();
    });
    side.replaceChildren(
      close,
      element('h2', '', ui.clusterReports(cluster.count)),
    );
    if (cluster.count > (cluster.ids?.length ?? 0))
      side.append(element('p', '', ui.clusterLimited));
    try {
      for (const id of cluster.ids ?? []) {
        const report = await api.getReport(id, { signal: own.signal });
        if (own.signal.aborted) return;
        const details = createReportDetails(report, {
          api,
          signal: own.signal,
        });
        details.querySelector('a.detail-link').href = filtersHash(
          `#/reports/${id}`,
          query(),
        );
        side.append(details);
      }
    } catch (error) {
      if (!own.signal.aborted) side.append(element('p', '', staffError(error)));
    }
  }
  /** Walk server pages in their stable API order, preserving the current filter. */
  async function getAdjacent(id, direction, signal) {
    let scanOffset = 0;
    let current = await api.getReports(
      { ...query(), offset: scanOffset },
      { signal },
    );
    let index = current.items.findIndex(
      (item) => item.id.toLowerCase() === id.toLowerCase(),
    );
    // A shared deep link may not belong to the first page. Search until found.
    while (index < 0 && scanOffset + 25 < current.total) {
      scanOffset += 25;
      current = await api.getReports(
        { ...query(), offset: scanOffset },
        { signal },
      );
      index = current.items.findIndex(
        (item) => item.id.toLowerCase() === id.toLowerCase(),
      );
    }
    if (index < 0) return null;
    if (current.items[index + direction])
      return current.items[index + direction].id;
    const nextOffset = scanOffset + direction * 25;
    if (nextOffset < 0 || nextOffset >= current.total) return null;
    const next = await api.getReports(
      { ...query(), offset: nextOffset },
      { signal },
    );
    return (direction > 0 ? next.items[0] : next.items.at(-1))?.id ?? null;
  }
  function scheduleLoad() {
    if (destroyed) return;
    needsLoad = true;
    if (!active) return;
    clearTimeout(timer);
    controller?.abort();
    const current = ++generation;
    store.startLoading();
    timer = setTimeout(async () => {
      controller = new AbortController();
      const own = controller;
      const filters = query();
      // Attach the error handler immediately so a failed cluster fetch cannot leak a rejection.
      const clusterResult = api
        .getClusters?.(
          { ...filters, zoom: map.getZoom?.() ?? 13 },
          { signal: own.signal },
        )
        .then(
          (body) => ({ body }),
          (error) => ({ error }),
        );
      try {
        const result = await api.getReports(
          {
            ...filters,
            ...(store.getState().offset
              ? { offset: store.getState().offset }
              : {}),
          },
          { signal: own.signal },
        );
        if (destroyed || current !== generation) return;
        if (
          store.getState().offset > 0 &&
          store.getState().offset >= result.total
        ) {
          store.setOffset(
            Math.max(0, Math.floor((result.total - 1) / 25) * 25),
          );
          scheduleLoad();
          return;
        }
        store.setReports(result);
        needsLoad = false;
        if (clusterResult) {
          try {
            const cluster = await clusterResult;
            if (destroyed || current !== generation) return;
            if (cluster.error) {
              side.replaceChildren(element('p', '', ui.clusterError));
              map.renderClusters?.([]);
              return;
            }
            // The cluster payload has no state. Hydrate singletons with bounded parallel reads.
            const reports = [];
            const ids = [
              ...new Set(
                cluster.body.clusters
                  .filter((c) => c.count === 1)
                  .flatMap((c) => c.ids ?? []),
              ),
            ];
            let index = 0;
            await Promise.all(
              Array.from({ length: Math.min(6, ids.length) }, async () => {
                while (index < ids.length) {
                  const id = ids[index++];
                  const cached = result.items.find(
                    (item) => item.id.toLowerCase() === id.toLowerCase(),
                  );
                  reports.push(
                    cached ?? (await api.getReport(id, { signal: own.signal })),
                  );
                }
              }),
            );
            if (!destroyed && current === generation)
              map.renderClusters?.(cluster.body.clusters, reports);
          } catch (error) {
            if (
              !destroyed &&
              current === generation &&
              error.name !== 'AbortError'
            ) {
              side.replaceChildren(element('p', '', ui.clusterError));
              map.renderClusters?.([]);
            }
          }
        }
      } catch (error) {
        if (destroyed || current !== generation || error.name === 'AbortError')
          return;
        map.renderClusters?.([]);
        store.setError(
          error instanceof ApiError
            ? error.error
            : { code: 'network_error', message: t.networkError },
        );
      }
    }, 300);
  }
  const map = mapFactory(mapElement, {
    onBoundsChange: () => {
      if (applyingRoute) return;
      store.setOffset(0);
      syncHash();
      scheduleLoad();
    },
    onSelect: (id) => {
      store.selectReport(id);
      showReport(id);
    },
    onCluster: showCluster,
    detailsFactory: (report) =>
      createReportDetails(report, { api, signal: controller?.signal }),
  });
  const panel = createPanel(panelElement, {
    onFiltersChange(filters) {
      store.setFilters(filters);
      syncHash();
      scheduleLoad();
    },
    onSelect(id) {
      store.selectReport(id);
      map.focusReport(id);
      showReport(id);
    },
    getScope: query,
    onRetry: scheduleLoad,
    onPage(offset) {
      store.setOffset(offset);
      scheduleLoad();
    },
  });
  panelElement.querySelector('.panel-header').after(staffRoot);
  panelElement.querySelector('.results').before(side);
  const toggle = element('button', 'map-toggle', ui.mapToggle);
  toggle.type = 'button';
  toggle.setAttribute('aria-expanded', 'false');
  toggle.addEventListener('click', () => {
    const shown = mapElement.parentElement.classList.toggle('map-visible');
    toggle.setAttribute('aria-expanded', String(shown));
    if (shown) map.invalidateSize?.();
  });
  panelElement.querySelector('.panel-header').after(toggle);
  const searchRoot = element('div');
  panelElement.querySelector('.panel-header').after(searchRoot);
  const search = createPlaceSearch(searchRoot, {
    onSelect: (place) => map.flyToPlace(place),
  });
  let previousReports, previousFilters;
  const unsubscribe = store.subscribe((state) => {
    panel.render(state);
    if (
      state.reports !== previousReports ||
      state.filters !== previousFilters
    ) {
      if (!api.getClusters)
        map.renderReports(filterReports(state.reports, state.filters));
      previousReports = state.reports;
      previousFilters = state.filters;
    }
  });
  function renderRoute(route) {
    const { bbox, ...parsed } = parseFilters(window.location.hash);
    const before = store.getState().filters;
    store.setFilters({ category: '', status: '', resolution: '', ...parsed });
    if (before !== store.getState().filters) needsLoad = true;
    applyingRoute = true;
    if (bbox && JSON.stringify(bbox) !== JSON.stringify(map.getBbox())) {
      map.setViewBounds?.(bbox);
      needsLoad = true;
    }
    applyingRoute = false;
    if (route.name === 'map' && currentRoute === 'map') {
      scheduleLoad();
      return;
    }
    currentRoute = route.name;
    page?.destroy();
    page = null;
    const wasActive = active;
    active = route.name === 'map';
    if (wasActive && !active) returnFocus = document.activeElement;
    workspaceElement.hidden = !active;
    pageElement.hidden = active;
    if (active) panelElement.querySelector('.panel-header').after(staffRoot);
    else pageElement.before(staffRoot);
    if (active) {
      map.invalidateSize?.();
      if (needsLoad) scheduleLoad();
      if (returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
      if (window.location.hash === '#reports-list')
        panelElement.querySelector('#reports-list').focus();
    } else {
      clearTimeout(timer);
      controller?.abort();
      sideController?.abort();
      generation++;
      search.cancel();
      if (route.name === 'report')
        page = createReportPage(pageElement, {
          api,
          id: route.id,
          mapFactory: locationMapFactory,
          staff,
          filters: query(),
          getAdjacent,
          onChanged: () => {
            needsLoad = true;
          },
        });
      else if (route.name === 'dashboard')
        page = createDashboard(pageElement, { api, filters: query() });
      else if (route.name === 'triage')
        page = createTriage(pageElement, {
          api,
          staff,
          filters: query(),
          onChanged: () => {
            needsLoad = true;
          },
        });
      else {
        const heading = element('h1', '', t.pageNotFound);
        heading.tabIndex = -1;
        const back = element('a', '', t.backToMap);
        back.href = filtersHash('#/', query());
        pageElement.replaceChildren(heading, back);
        heading.focus();
      }
    }
  }
  if (initialBounds) {
    applyingRoute = true;
    map.setViewBounds?.(initialBounds);
    applyingRoute = false;
  }
  if (pageElement && workspaceElement) router = createRouter(renderRoute);
  else scheduleLoad();
  const unsubscribeStaff = staff.subscribe(() => {
    sideController?.abort();
    sideActions?.destroy();
    side.replaceChildren();
    store.setReports({ items: [], total: 0 });
    map.renderClusters?.([]);
    needsLoad = true;
    if (router) {
      currentRoute = null;
      renderRoute(parseRoute(window.location.hash));
    } else scheduleLoad();
  });
  return {
    store,
    router,
    staff,
    destroy() {
      destroyed = true;
      generation++;
      clearTimeout(timer);
      controller?.abort();
      sideController?.abort();
      sideActions?.destroy();
      unsubscribeStaff();
      unsubscribe();
      router?.destroy();
      page?.destroy();
      search.destroy();
      staffPanel.destroy();
      staffRoot.remove();
      staff.destroy();
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
