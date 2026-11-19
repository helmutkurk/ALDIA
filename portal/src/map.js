import L from 'leaflet';
import { reportState, STATE_GROUPS, stateLabel } from './states.js';
import { ui } from './i18n.js';
import { categoryLabel } from './categories.js';
import { createReportDetails } from './panel.js';
import { statusLabel, t } from './i18n.js';

const CENTER = [14.6349, -90.5069];

/**
 * Leaflet is confined to this module; the store never contains map objects.
 * @param {HTMLElement} container
 * @param {{onBoundsChange: () => void, onSelect: (id: string) => void, center?: number[], zoom?: number}} callbacks
 */
export function createReportMap(
  container,
  {
    onBoundsChange,
    onSelect,
    onCluster = () => {},
    detailsFactory = createReportDetails,
    center = CENTER,
    zoom = 13,
  },
) {
  container.setAttribute('role', 'region');
  container.setAttribute('aria-label', t.mapLabel);
  container.setAttribute('aria-describedby', 'map-help');
  const map = L.map(container, {
    center,
    zoom,
    minZoom: 3,
    maxZoom: 19,
    maxBounds: [
      [-85, -180],
      [85, 180],
    ],
    maxBoundsViscosity: 1,
    zoomControl: false,
    trackResize: false,
  });
  L.control
    .zoom({
      position: 'bottomright',
      zoomInTitle: t.zoomIn,
      zoomOutTitle: t.zoomOut,
    })
    .addTo(map);
  // Attribution is fixed, trusted content, never supplied by the API.
  const tiles = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    noWrap: true,
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);
  map.attributionControl.setPrefix(false);
  container
    .querySelector('.leaflet-control-zoom-in')
    .setAttribute('aria-label', t.zoomIn);
  container
    .querySelector('.leaflet-control-zoom-out')
    .setAttribute('aria-label', t.zoomOut);
  const tileMessage = document.createElement('p');
  tileMessage.className = 'tile-error';
  tileMessage.setAttribute('role', 'status');
  tileMessage.textContent = t.mapTilesError;
  tileMessage.hidden = true;
  container.parentElement.append(tileMessage);
  const onTileError = () => {
    tileMessage.hidden = false;
  };
  const onTileLoad = () => {
    tileMessage.hidden = true;
  };
  tiles.on('tileerror', onTileError);
  tiles.on('tileload', onTileLoad);
  /** @type {Map<string, import('leaflet').Marker>} */
  const markers = new Map();
  const clusters = [];
  const clearClusters = () => {
    clusters.forEach((marker) => marker.remove());
    clusters.length = 0;
  };
  let openedId = null;
  let focusReturn = null;
  let refreshing = false;
  let pendingFocus = null;
  const onPopupOpen = ({ popup }) => {
    const close = popup
      .getElement()
      ?.querySelector('.leaflet-popup-close-button');
    close?.setAttribute('aria-label', t.closePopup);
    close?.setAttribute('title', t.closePopup);
  };
  const onPopupClose = () => {
    if (refreshing) return;
    openedId = null;
    if (focusReturn?.isConnected) focusReturn.focus({ preventScroll: true });
    focusReturn = null;
  };
  const onKeyDown = (event) => {
    if (event.key === 'Escape') map.closePopup();
  };
  map.on('popupopen', onPopupOpen);
  map.on('popupclose', onPopupClose);
  map.on('moveend', onBoundsChange);
  container.addEventListener('keydown', onKeyDown);
  // Hidden routes must never resize Leaflet to a zero-size viewport. Handle
  // both element and window resizes here instead of Leaflet's default listener.
  const resizeIfVisible = () => {
    if (container.clientWidth && container.clientHeight)
      map.invalidateSize({ pan: false });
  };
  const observer =
    typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver(resizeIfVisible);
  observer?.observe(container);
  window.addEventListener('resize', resizeIfVisible);
  return {
    /** @returns {import('./api.js').Bbox} */
    getBbox() {
      const bounds = map.getBounds();
      // Do not send wrapped longitudes or latitudes outside the geographic range.
      return [
        Math.max(-180, bounds.getWest()),
        Math.max(-90, bounds.getSouth()),
        Math.min(180, bounds.getEast()),
        Math.min(90, bounds.getNorth()),
      ];
    },
    getZoom: () => map.getZoom(),
    setViewBounds(bounds) {
      map.fitBounds(
        [
          [bounds[1], bounds[0]],
          [bounds[3], bounds[2]],
        ],
        { animate: false },
      );
    },
    /** Cluster markers contain counts only; singleton identities are hydrated through detail reads.
     * @param {object[]} items @param {object[]} [reports] */
    renderClusters(items, reports = []) {
      clearClusters();
      this.renderReports(reports);
      for (const cluster of items) {
        if (
          cluster.count === 1 &&
          reports.some((report) => cluster.ids?.includes(report.id))
        )
          continue;
        const bubble = document.createElement('span');
        bubble.className = 'cluster-count';
        bubble.textContent = String(cluster.count);
        const label = ui.cluster(cluster.count);
        const marker = L.marker([cluster.lat, cluster.lon], {
          icon: L.divIcon({
            html: bubble,
            className: 'cluster-marker',
            iconSize: [48, 48],
          }),
          keyboard: true,
          title: label,
          alt: label,
        }).addTo(map);
        marker.getElement().setAttribute('aria-label', label);
        marker.on('click', () => {
          if (map.getZoom() < map.getMaxZoom())
            map.setView(
              [cluster.lat, cluster.lon],
              Math.min(map.getMaxZoom(), map.getZoom() + 2),
              { animate: false },
            );
          else onCluster(cluster);
        });
        clusters.push(marker);
      }
    },
    /** @param {ReadonlyArray<import('./api.js').Report>} reports */
    renderReports(reports) {
      const restoreId = openedId;
      const focusedMarkerId = [...markers].find(
        ([, marker]) => marker.getElement() === document.activeElement,
      )?.[0];
      const focusInPopup = markers
        .get(restoreId)
        ?.getPopup()
        ?.getElement()
        ?.contains(document.activeElement);
      refreshing = true;
      markers.forEach((marker) => marker.remove());
      markers.clear();
      for (const report of reports) {
        const pin = document.createElement('span');
        pin.className = `status-pin status-pin--${report.status} state-pin--${STATE_GROUPS[reportState(report)]}`;
        pin.dataset.letter = ui.groupLetters[STATE_GROUPS[reportState(report)]];
        pin.setAttribute('aria-hidden', 'true');
        const label = t.selectReport(
          categoryLabel(report.category),
          `${stateLabel(reportState(report))}. ${statusLabel(report)}`,
        );
        const marker = L.marker([report.latitude, report.longitude], {
          icon: L.divIcon({
            html: pin,
            className: 'report-marker',
            iconSize: [44, 54],
            iconAnchor: [22, 50],
            popupAnchor: [0, -46],
          }),
          title: label,
          alt: label,
          keyboard: true,
        }).addTo(map);
        marker.getElement().setAttribute('aria-label', label);
        marker.bindPopup(() => detailsFactory(report), {
          maxWidth: 320,
          minWidth: 220,
          autoPan: true,
          autoPanPadding: [16, 16],
        });
        marker.on('click', () => {
          openedId = report.id;
          focusReturn = marker.getElement();
          onSelect(report.id);
        });
        markers.set(report.id, marker);
      }
      openedId = markers.has(restoreId) ? restoreId : null;
      if (openedId) {
        const marker = markers.get(openedId);
        marker.openPopup();
        if (!focusReturn?.isConnected) focusReturn = marker.getElement();
        if (focusInPopup)
          marker
            .getPopup()
            .getElement()
            ?.querySelector('h2')
            ?.focus({ preventScroll: true });
      }
      if (focusedMarkerId)
        markers
          .get(focusedMarkerId)
          ?.getElement()
          ?.focus({ preventScroll: true });
      refreshing = false;
    },
    /** @param {{latitude: number, longitude: number}} place */
    flyToPlace({ latitude, longitude }) {
      map.flyTo([latitude, longitude], 15, {
        animate: !(
          window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ??
          false
        ),
        duration: 0.6,
      });
    },
    /** Recalculate dimensions after returning to the retained map view. */
    invalidateSize() {
      map.invalidateSize({ pan: false });
    },
    /** @param {string} id */
    focusReport(id) {
      const marker = markers.get(id);
      if (!marker) return;
      const returnTarget = document.activeElement;
      if (pendingFocus) map.off('moveend', pendingFocus);
      // Open after the flight so Leaflet can keep the whole popup in view.
      pendingFocus = () => {
        pendingFocus = null;
        const current = markers.get(id);
        if (!current) return;
        current.openPopup();
        openedId = id;
        focusReturn = returnTarget;
        current
          .getPopup()
          .getElement()
          ?.querySelector('h2')
          ?.focus({ preventScroll: true });
      };
      map.once('moveend', pendingFocus);
      const reducedMotion =
        window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ??
        false;
      map.flyTo(marker.getLatLng(), Math.max(map.getZoom(), 16), {
        animate: !reducedMotion,
        duration: 0.6,
      });
    },
    destroy() {
      observer?.disconnect();
      window.removeEventListener('resize', resizeIfVisible);
      container.removeEventListener('keydown', onKeyDown);
      map.off('moveend', onBoundsChange);
      map.off('popupopen', onPopupOpen);
      map.off('popupclose', onPopupClose);
      tileMessage.remove();
      map.remove();
    },
  };
}

/** A compact location map using the same tile, attribution and keyboard behavior.
 * @param {HTMLElement} container @param {import('./api.js').Report} report
 */
export function createLocationMap(container, report, photoOptions = {}) {
  const map = createReportMap(container, {
    onBoundsChange() {},
    onSelect() {},
    detailsFactory: (item) => createReportDetails(item, photoOptions),
    center: [report.latitude, report.longitude],
    zoom: 16,
  });
  container.setAttribute('aria-label', t.location);
  container.removeAttribute('aria-describedby');
  map.renderReports([report]);
  return map;
}
