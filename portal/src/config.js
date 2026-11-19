// Portal configuration. Defaults run the demo with synthetic data. To use the backend, open the
// portal with `?source=api&api=<base url>` or change the defaults here.

/**
 * Map tiles. OpenStreetMap's own tile server is only for development and demos (its usage policy
 * forbids heavy production use). For production, pick a tile provider or self-host; Google Maps can
 * replace this through the map adapter in ui/map-view.js.
 */
export const TILE_PROVIDERS = Object.freeze({
  osm: {
    url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    maxZoom: 19,
  },
});

export const DEFAULT_CONFIG = Object.freeze({
  source: "mock",
  apiBaseUrl: "/api/v1",
  pollMs: 15_000,
  municipality: "Municipalidad de ejemplo · Ciudad de Guatemala",
  agency: "Municipalidad de Guatemala",
  map: { tiles: "osm", center: [14.6215, -90.5165], zoom: 13 },
});

export function readConfig(search = "") {
  const params = new URLSearchParams(search);
  const source = params.get("source") === "api" ? "api" : DEFAULT_CONFIG.source;
  const api = params.get("api");
  const apiBaseUrl = api && /^(https?:\/\/|\/)[^\s]*$/.test(api) ? api : DEFAULT_CONFIG.apiBaseUrl;
  return { ...DEFAULT_CONFIG, source, apiBaseUrl };
}
