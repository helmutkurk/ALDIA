import { uuidPattern } from './api.js';

/** @typedef {{name: 'map'|'dashboard'|'not-found'}|{name: 'report', id: string}} Route */
/** @param {string} hash @returns {Route} */
export function parseRoute(hash) {
  if (hash === '' || hash === '#/' || hash === '#reports-list')
    return { name: 'map' };
  if (hash === '#/panel') return { name: 'dashboard' };
  const match = /^#\/reports\/([^/]+)$/.exec(hash);
  if (match && uuidPattern.test(match[1]))
    return { name: 'report', id: match[1] };
  return { name: 'not-found' };
}

/** Browser back/forward uses native hash history; rendering remains with the owner.
 * @param {(route: Route) => void} onRoute
 */
export function createRouter(onRoute) {
  const render = () => onRoute(parseRoute(window.location.hash));
  window.addEventListener('hashchange', render);
  render();
  return {
    /** @param {string} hash */
    navigate(hash) {
      window.location.hash = hash;
    },
    destroy() {
      window.removeEventListener('hashchange', render);
    },
  };
}
