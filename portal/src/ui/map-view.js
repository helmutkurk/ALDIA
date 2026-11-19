// Map adapter. Today it draws with Leaflet and OpenStreetMap tiles (the same approach FixMyStreet
// takes with OpenLayers + OSM). The rest of the portal only calls render(), focus() and resize(),
// so a Google Maps version can replace this file without touching anything else.

import { h } from "./dom.js";
import { clusterPoints } from "../domain/cluster.js";
import { categoryLabel } from "../domain/categories.js";
import { statusLabel } from "../domain/statuses.js";

const CLUSTER_UNTIL_ZOOM = 16;
const CELL_PX = 56;

export function createMapView(container, { center, zoom, tiles, onSelect }) {
  const L = globalThis.L;
  if (!L) {
    container.replaceChildren(
      h("p", { class: "map-error" }, "No se pudo cargar el mapa. Revisa la conexión a internet y recarga la página."),
    );
    return { render() {}, focus() {}, resize() {} };
  }

  const map = L.map(container, { zoomControl: true }).setView(center, zoom);
  L.tileLayer(tiles.url, { maxZoom: tiles.maxZoom, attribution: tiles.attribution }).addTo(map);
  const layer = L.layerGroup().addTo(map);
  let state = { cases: [], selectedId: null };

  function caseIcon(c, selected) {
    const size = 16 + Math.min(c.reporterCount, 6) * 2;
    const classes = ["pin", `st-${c.status}`];
    if (selected) classes.push("is-selected");
    if (c.open && c.severity === "dangerous") classes.push("is-urgent");
    const el = h(
      "span",
      { class: classes.join(" "), style: { "--size": `${size}px` } },
      c.reporterCount > 2 ? String(c.reporterCount) : "",
    );
    return L.divIcon({ html: el, className: "pin-wrap", iconSize: [size, size], iconAnchor: [size / 2, size / 2] });
  }

  function clusterIcon(count, urgent) {
    const size = 28 + Math.min(count, 20);
    const el = h("span", { class: `cluster${urgent ? " has-urgent" : ""}`, style: { "--size": `${size}px` } }, String(count));
    return L.divIcon({ html: el, className: "pin-wrap", iconSize: [size, size], iconAnchor: [size / 2, size / 2] });
  }

  const tooltip = (c) =>
    h("div", { class: "tip" }, h("strong", {}, categoryLabel(c.category)), h("span", {}, c.address ?? c.id), h("span", {}, statusLabel(c.status)));

  function draw() {
    layer.clearLayers();
    const z = map.getZoom();
    const points = state.cases.map((c) => {
      const p = map.project([c.lat, c.lng], z);
      return { x: p.x, y: p.y, c };
    });
    const groups =
      z >= CLUSTER_UNTIL_ZOOM ? points.map((p) => ({ x: p.x, y: p.y, members: [p] })) : clusterPoints(points, CELL_PX);

    for (const g of groups) {
      if (g.members.length === 1 || g.members.some((m) => m.c.id === state.selectedId)) {
        for (const { c } of g.members) {
          const selected = c.id === state.selectedId;
          const marker = L.marker([c.lat, c.lng], {
            icon: caseIcon(c, selected),
            title: `${categoryLabel(c.category)}: ${c.address ?? c.id}`,
            riseOnHover: true,
            zIndexOffset: selected ? 10_000 : c.priority * 10,
          });
          marker.bindTooltip(tooltip(c), { direction: "top", offset: [0, -10] });
          marker.on("click", () => onSelect(c.id));
          marker.addTo(layer);
        }
      } else {
        const where = map.unproject([g.x, g.y], z);
        const urgent = g.members.some((m) => m.c.open && m.c.severity === "dangerous");
        const marker = L.marker(where, { icon: clusterIcon(g.members.length, urgent), title: `${g.members.length} casos` });
        marker.on("click", () => map.setView(where, Math.min(z + 2, CLUSTER_UNTIL_ZOOM)));
        marker.addTo(layer);
      }
    }
  }

  map.on("zoomend", draw);

  return {
    render(cases, selectedId) {
      state = { cases, selectedId };
      draw();
    },
    focus(c) {
      map.setView([c.lat, c.lng], Math.max(map.getZoom(), CLUSTER_UNTIL_ZOOM), { animate: true });
    },
    resize() {
      map.invalidateSize();
    },
  };
}
