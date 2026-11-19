import { createLocationMap } from './map.js';
import { createReportDetails, element } from './panel.js';
import { t } from './i18n.js';

/** Standalone, cancellable report view. Report strings are never interpreted as HTML.
 * @param {HTMLElement} root
 * @param {{id: string, api: Pick<ReturnType<import('./api.js').createApiClient>, 'getReport'>, mapFactory?: typeof createLocationMap}} options
 */
export function createReportPage(
  root,
  { id, api, mapFactory = createLocationMap },
) {
  let controller;
  let map;
  let generation = 0;
  const back = element('a', 'back-link', t.backToMap);
  back.href = '#/';
  async function load() {
    controller?.abort();
    map?.destroy();
    map = null;
    controller = new AbortController();
    const current = ++generation;
    const loading = element('p', '', t.reportLoading);
    loading.setAttribute('role', 'status');
    root.replaceChildren(back, loading);
    root.setAttribute('aria-busy', 'true');
    try {
      const report = await api.getReport(id, { signal: controller.signal });
      if (current !== generation) return;
      const details = createReportDetails(report);
      const title = element('h1', '', details.querySelector('h2').textContent);
      title.tabIndex = -1;
      details.querySelector('h2').replaceWith(title);
      details.querySelector('.detail-link').remove();
      const checksHeading = details.querySelector('h3');
      checksHeading.replaceWith(element('h2', '', checksHeading.textContent));
      const location = element('section', 'report-location');
      const locationTitle = element('h2', '', t.location);
      const mapElement = element('div', 'location-map');
      mapElement.tabIndex = 0;
      location.append(locationTitle, mapElement);
      root.replaceChildren(back, details, location);
      map = mapFactory(mapElement, report);
      title.focus({ preventScroll: true });
    } catch (error) {
      if (current !== generation || error.name === 'AbortError') return;
      const message = element(
        'p',
        'error-message',
        error.status === 404 ? t.reportNotFound : t.reportError,
      );
      message.setAttribute('role', 'alert');
      const retry = element('button', 'retry-button', t.retry);
      retry.type = 'button';
      retry.addEventListener('click', load);
      root.replaceChildren(back, message, retry);
    } finally {
      if (current === generation) root.setAttribute('aria-busy', 'false');
    }
  }
  load();
  return {
    destroy() {
      generation++;
      controller?.abort();
      map?.destroy();
      map = null;
      root.replaceChildren();
      root.removeAttribute('aria-busy');
    },
  };
}
