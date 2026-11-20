import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { createCsvExport } from '../src/csv-export.js';
import { ui } from '../src/i18n.js';

let exporter;
let createUrl, revokeUrl, download;
const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};
const click = (node) =>
  node.dispatchEvent(
    new window.MouseEvent('click', { bubbles: true, cancelable: true }),
  );
beforeEach(() => {
  createUrl = vi
    .fn()
    .mockReturnValueOnce('blob:first')
    .mockReturnValueOnce('blob:second');
  revokeUrl = vi.fn();
  vi.stubGlobal(
    'URL',
    class extends URL {
      static createObjectURL = createUrl;
      static revokeObjectURL = revokeUrl;
    },
  );
  download = vi
    .spyOn(window.HTMLAnchorElement.prototype, 'click')
    .mockImplementation(() => {});
});
afterEach(() => {
  exporter?.destroy();
  document.body.replaceChildren();
  vi.unstubAllGlobals();
});

it('retains scope and delimiter across renders, prevents duplicate downloads and releases URLs', async () => {
  const filters = { category: 'pothole', state: 'nuevo' };
  let respond;
  const api = {
    getCsvUrl: vi.fn(() => '/api/reports.csv'),
    getCsvBlob: vi.fn(
      () =>
        new Promise((resolve) => {
          respond = resolve;
        }),
    ),
  };
  exporter = createCsvExport({ api, filters });
  const options = {
    signal: new AbortController().signal,
    isCurrent: () => true,
  };
  let section = exporter.render(options);
  document.body.append(section);
  const select = section.querySelector('select');
  select.value = 'semicolon';
  select.dispatchEvent(new window.Event('change'));
  const csv = section.querySelector('.csv-link');
  click(csv);
  click(csv);
  expect(api.getCsvBlob).toHaveBeenCalledExactlyOnceWith(
    { ...filters, delimiter: 'semicolon' },
    { signal: options.signal },
  );
  expect(csv.getAttribute('aria-disabled')).toBe('true');
  respond(new window.Blob(['first']));
  await flush();
  expect(download).toHaveBeenCalledOnce();
  expect(csv.getAttribute('aria-disabled')).toBe('false');
  section.remove();
  section = exporter.render(options);
  document.body.append(section);
  expect(section.querySelector('select').value).toBe('semicolon');
  expect(api.getCsvUrl).toHaveBeenLastCalledWith({
    ...filters,
    delimiter: 'semicolon',
  });
  expect(revokeUrl).not.toHaveBeenCalled();
  click(section.querySelector('.csv-link'));
  respond(new window.Blob(['second']));
  await flush();
  expect(revokeUrl).toHaveBeenCalledExactlyOnceWith('blob:first');
  exporter.destroy();
  exporter.destroy();
  expect(revokeUrl.mock.calls).toEqual([['blob:first'], ['blob:second']]);
});

it('ignores late downloads when their dashboard generation is obsolete', async () => {
  let respond,
    current = true;
  exporter = createCsvExport({
    api: {
      getCsvUrl: () => '/api/reports.csv',
      getCsvBlob: () =>
        new Promise((resolve) => {
          respond = resolve;
        }),
    },
    filters: {},
  });
  const controller = new AbortController();
  const section = exporter.render({
    signal: controller.signal,
    isCurrent: () => current,
  });
  document.body.append(section);
  click(section.querySelector('.csv-link'));
  current = false;
  controller.abort();
  exporter.destroy();
  section.remove();
  respond(new window.Blob(['late']));
  await flush();
  expect(createUrl).not.toHaveBeenCalled();
  expect(download).not.toHaveBeenCalled();
  expect(document.body.childElementCount).toBe(0);
});

it('shows the canonical staff error and permits a retry after failure', async () => {
  const api = {
    getCsvUrl: () => '/api/reports.csv',
    getCsvBlob: vi
      .fn()
      .mockRejectedValueOnce({ status: 403 })
      .mockResolvedValueOnce(new window.Blob(['csv'])),
  };
  exporter = createCsvExport({ api, filters: {} });
  const section = exporter.render({
    signal: new AbortController().signal,
    isCurrent: () => true,
  });
  document.body.append(section);
  const csv = section.querySelector('.csv-link');
  click(csv);
  await flush();
  expect(section.querySelector('[role="status"]').textContent).toBe(
    ui.forbidden,
  );
  expect(csv.getAttribute('aria-disabled')).toBe('false');
  click(csv);
  await flush();
  expect(section.querySelector('[role="status"]').textContent).toBe('');
  expect(download).toHaveBeenCalledOnce();
});
