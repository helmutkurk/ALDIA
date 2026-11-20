import 'leaflet/dist/leaflet.css';
import './styles/tokens.css';
import './styles/app.css';
import { ApiError, createApiClient } from './api.js';
import { createReportMap } from './map.js';
import { createDashboard } from './dashboard.js';
import { createPlaceSearch } from './geocoder.js';
import { createReportPage } from './report.js';
import { createRouter, parseRoute } from './router.js';
import { createPanel } from './panel.js';
import { createReportDetails } from './report-details.js';
import { element } from './dom.js';
import { createStore, filterReports } from './state.js';
import { parseFilters, filtersHash } from './filters.js';
import { createStaffSession, createStaffPanel } from './staff.js';
import { getAdjacentReport } from './adjacent-report.js';
import { createSelection } from './selected-report.js';
import { createSiteHeader } from './header.js';
import { mountPortal } from './mount.js';
import { createTriage } from './triage.js';
import { ui, t } from './i18n.js';

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
  headerElement,
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
  let timer, controller, page, returnFocus, router;
  let generation = 0,
    destroyed = false,
    active = true,
    needsLoad = true,
    applyingRoute = false,
    currentRoute;
  const side = element('section', 'selected-report');
  const staffRoot = element('div', 'staff-root');
  staffRoot.id = 'staff-access';
  const staffPanel = createStaffPanel(staffRoot, staff, api);
  staffRoot.hidden = true;
  const query = () => ({ ...store.getState().filters, bbox: map.getBbox() });
  const selection = createSelection(side, {
    api,
    staff,
    getScope: query,
    onSaved: scheduleLoad,
  });
  const syncHash = () => {
    if (pageElement && active && currentRoute === 'map' && !applyingRoute)
      window.history.replaceState(null, '', filtersHash('#/', query()));
  };
  const getAdjacent = (id, direction, signal) =>
    getAdjacentReport(api, query, id, direction, signal);
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
          {
            ...filters,
            zoom: (map.getZoom?.() ?? 13) >= 15 ? 17 : (map.getZoom?.() ?? 13),
          },
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
      selection.showReport(id);
    },
    onCluster: selection.showCluster,
    detailsFactory: (report) =>
      createReportDetails(report, { api, signal: controller?.signal }),
  });
  const panel = createPanel(panelElement, {
    api,
    onFiltersChange(filters) {
      store.setFilters(filters);
      syncHash();
      scheduleLoad();
    },
    onSelect(id) {
      store.selectReport(id);
      map.focusReport(
        id,
        store.getState().reports.find((report) => report.id === id),
      );
      selection.showReport(id);
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
  const toggle = element('button', 'map-toggle', ui.showMap);
  toggle.type = 'button';
  toggle.setAttribute('aria-expanded', 'false');
  toggle.setAttribute('aria-label', ui.mapToggle);
  toggle.addEventListener('click', () => {
    const shown = mapElement.parentElement.classList.toggle('map-visible');
    toggle.setAttribute('aria-expanded', String(shown));
    toggle.textContent = shown ? ui.showList : ui.showMap;
    if (shown) map.invalidateSize?.();
    else panelElement.scrollTo?.(0, 0);
  });
  // Phones show the list first; the toggle lives outside the scrolling panel.
  panelElement.before(toggle);
  const header = headerElement
    ? createSiteHeader(headerElement, {
        onStaff() {
          staffRoot.hidden = !staffRoot.hidden;
          const details = staffRoot.querySelector('details');
          if (details) details.open = !staffRoot.hidden;
          // On phones the list may hide the panel behind the map view.
          mapElement.parentElement.classList.remove('map-visible');
          toggle.setAttribute('aria-expanded', 'false');
          toggle.textContent = ui.showMap;
          if (staffRoot.hidden) return false;
          staffRoot.scrollIntoView?.({ block: 'start' });
          [...staffRoot.querySelectorAll('input, button')]
            .find((control) => !control.closest('[hidden]'))
            ?.focus();
          return true;
        },
      })
    : null;
  const searchRoot = element('div');
  panelElement.querySelector('.panel-header').after(searchRoot);
  const search = createPlaceSearch(searchRoot, {
    onSelect: (place) => map.flyToPlace(place),
  });
  let previousReports, previousFilters;
  const unsubscribe = store.subscribe((state) => {
    panel.render(state);
    header?.update(query());
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
    header?.setRoute(route.name);
    page?.destroy();
    page = null;
    const wasActive = active;
    active = route.name === 'map';
    if (wasActive && !active) returnFocus = document.activeElement;
    workspaceElement.hidden = !active;
    pageElement.hidden = active;
    toggle.hidden = !active;
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
      selection.clear();
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
  let hadStaff = Boolean(staff.getRole?.() || staff.getToken?.());
  const unsubscribeStaff = staff.subscribe(() => {
    const authenticated = Boolean(staff.getRole?.() || staff.getToken?.());
    if (hadStaff && !authenticated) {
      staffRoot.hidden = false;
      staffRoot.querySelector('details').open = true;
    }
    hadStaff = authenticated;
    header?.setStaffOpen(!staffRoot.hidden);
    selection.clear();
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
      selection.clear();
      unsubscribeStaff();
      unsubscribe();
      header?.destroy();
      toggle.remove();
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
mountPortal(createPortal);
