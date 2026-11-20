import { ApiError } from './api.js';
import { element } from './dom.js';
import { ui, t } from './i18n.js';

/** Cluster detail reads reuse list reports and never exceed six concurrent requests.
 * @param {ReturnType<import('./api.js').createApiClient>} api
 * @param {import('./api-types.js').Cluster[]} clusters
 * @param {import('./api-types.js').Report[]} cached
 * @param {AbortSignal} signal
 * @returns {Promise<import('./api-types.js').Report[]>}
 */
async function hydrateSingletons(api, clusters, cached, signal) {
  const ids = [
    ...new Set(
      clusters.filter((c) => c.count === 1).flatMap((c) => c.ids ?? []),
    ),
  ];
  const reports = [];
  let index = 0;
  await Promise.all(
    Array.from({ length: Math.min(6, ids.length) }, async () => {
      while (index < ids.length) {
        const id = ids[index++];
        const report = cached.find(
          (item) => item.id.toLowerCase() === id.toLowerCase(),
        );
        reports.push(report ?? (await api.getReport(id, { signal })));
      }
    }),
  );
  return reports;
}

/** Load one workspace generation. The caller owns debounce and cancellation.
 * A cluster failure cannot discard a successful list; rendering waits for hydration.
 * @param {object} options
 * @param {ReturnType<import('./api.js').createApiClient>} options.api
 * @param {ReturnType<import('./map.js').createReportMap>} options.map
 * @param {ReturnType<import('./state.js').createStore>} options.store
 * @param {HTMLElement} options.side
 * @param {import('./api-types.js').ReportQuery} options.filters
 * @param {AbortSignal} options.signal
 * @param {() => boolean} options.isCurrent
 * @param {() => void} options.onLoaded
 * @param {() => void} options.reload
 */
export async function loadWorkspace({
  api,
  map,
  store,
  side,
  filters,
  signal,
  isCurrent,
  onLoaded,
  reload,
}) {
  // Observe rejection immediately, even while the independent list is pending.
  const clusters = api
    .getClusters?.(
      {
        ...filters,
        zoom: (map.getZoom?.() ?? 13) >= 15 ? 17 : (map.getZoom?.() ?? 13),
      },
      { signal },
    )
    .then(
      (body) => ({ body }),
      (error) => ({ error }),
    );
  let page;
  try {
    const offset = store.getState().offset;
    page = await api.getReports(
      { ...filters, ...(offset ? { offset } : {}) },
      { signal },
    );
    if (!isCurrent()) return;
    if (store.getState().offset > 0 && store.getState().offset >= page.total) {
      store.setOffset(Math.max(0, Math.floor((page.total - 1) / 25) * 25));
      reload();
      return;
    }
    store.setReports(page);
    onLoaded();
  } catch (error) {
    if (!isCurrent() || error.name === 'AbortError') return;
    map.renderClusters?.([]);
    store.setError(
      error instanceof ApiError
        ? error.error
        : { code: 'network_error', message: t.networkError },
    );
    return;
  }
  if (!clusters) return;
  try {
    const result = await clusters;
    if (!isCurrent()) return;
    if (result.error) throw result.error;
    const reports = await hydrateSingletons(
      api,
      result.body.clusters,
      page.items,
      signal,
    );
    if (isCurrent()) map.renderClusters?.(result.body.clusters, reports);
  } catch (error) {
    if (!isCurrent() || error.name === 'AbortError') return;
    side.replaceChildren(element('p', '', ui.clusterError));
    map.renderClusters?.([]);
  }
}
