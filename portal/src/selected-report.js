import { element } from './dom.js';
import { createReportDetails } from './report-details.js';
import { createStaffActions } from './actions.js';
import { filtersHash } from './filters.js';
import { ui, staffError, t } from './i18n.js';

export function createSelection(side, { api, staff, getScope, onSaved }) {
  let controller, actions, returnFocus;
  const rememberFocus = () => {
    if (!side.contains(document.activeElement))
      returnFocus = document.activeElement;
  };
  const clear = () => {
    controller?.abort();
    actions?.destroy();
    side.replaceChildren();
  };
  const closeButton = () => {
    const close = element('button', '', t.closePopup);
    close.type = 'button';
    close.addEventListener('click', () => {
      clear();
      if (returnFocus?.isConnected) returnFocus.focus();
    });
    return close;
  };
  async function showReport(id) {
    rememberFocus();
    controller?.abort();
    actions?.destroy();
    controller = new AbortController();
    const own = controller;
    side.replaceChildren(element('p', '', t.reportLoading));
    try {
      const report = await api.getReport(id, { signal: own.signal });
      if (own.signal.aborted) return;
      const close = closeButton();
      const details = createReportDetails(report, { api, signal: own.signal });
      details.querySelector('a.detail-link').href = filtersHash(
        `#/reports/${id}`,
        getScope(),
      );
      const controls = element('div');
      side.replaceChildren(close, details, controls);
      actions = createStaffActions(controls, {
        report,
        api,
        staff,
        onSaved: () => {
          showReport(id);
          onSaved();
        },
      });
      details.querySelector('h2').focus();
    } catch (error) {
      if (!own.signal.aborted) {
        const alert = element('p', 'error-message', staffError(error));
        alert.setAttribute('role', 'alert');
        const retry = element('button', 'retry-button', t.retry);
        retry.type = 'button';
        retry.addEventListener('click', () => showReport(id));
        side.replaceChildren(closeButton(), alert, retry);
      }
    }
  }
  async function showCluster(cluster) {
    rememberFocus();
    controller?.abort();
    actions?.destroy();
    controller = new AbortController();
    const own = controller;
    const close = closeButton();
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
          getScope(),
        );
        side.append(details);
      }
    } catch (error) {
      if (!own.signal.aborted) side.append(element('p', '', staffError(error)));
    }
  }
  return {
    showReport,
    showCluster,
    clear,
  };
}
