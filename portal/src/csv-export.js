import { element } from './dom.js';
import { t, staffError } from './i18n.js';

/** Dashboard-owned download state survives retries and is released on teardown.
 * @param {{api: ReturnType<import('./api.js').createApiClient>, filters: import('./api-types.js').ReportQuery}} options
 */
export function createCsvExport({ api, filters }) {
  let delimiter = 'comma';
  let objectUrl;
  const revoke = () => {
    if (objectUrl) {
      URL.revokeObjectURL(objectUrl);
      objectUrl = null;
    }
  };
  return {
    /** @param {{signal: AbortSignal, isCurrent: () => boolean}} options */
    render({ signal, isCurrent }) {
      const csv = element('a', 'csv-link', t.downloadCsv);
      const updateCsv = () => {
        csv.href = api.getCsvUrl({ ...filters, delimiter });
      };
      updateCsv();
      csv.download = 'reportes.csv';
      const status = element('p');
      status.setAttribute('role', 'status');
      const section = element('section', 'export-box dash-block');
      if (api.getCsvBlob)
        csv.addEventListener('click', async (event) => {
          event.preventDefault();
          if (csv.getAttribute('aria-disabled') === 'true') return;
          csv.setAttribute('aria-disabled', 'true');
          status.textContent = t.dash.csvLoading;
          try {
            const blob = await api.getCsvBlob(
              { ...filters, delimiter },
              { signal },
            );
            if (!isCurrent()) return;
            revoke();
            objectUrl = URL.createObjectURL(blob);
            const download = element('a');
            download.href = objectUrl;
            download.download = 'reportes.csv';
            section.append(download);
            download.click();
            download.remove();
            status.textContent = '';
          } catch (error) {
            if (isCurrent() && error.name !== 'AbortError')
              status.textContent = staffError(error);
          } finally {
            if (isCurrent()) csv.setAttribute('aria-disabled', 'false');
          }
        });
      const label = element('label', '', t.dash.delimiter);
      const select = document.createElement('select');
      select.setAttribute('aria-label', t.dash.delimiter);
      for (const id of ['comma', 'semicolon']) {
        const option = element('option', '', t.dash[id]);
        option.value = id;
        select.append(option);
      }
      select.value = delimiter;
      select.addEventListener('change', () => {
        delimiter = select.value;
        updateCsv();
      });
      label.append(select);
      section.append(element('h2', '', t.dash.exportData), label, csv, status);
      return section;
    },
    destroy: revoke,
  };
}
