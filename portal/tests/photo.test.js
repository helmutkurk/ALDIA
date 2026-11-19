import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { createPhoto } from '../src/photo.js';
import { createApiClient } from '../src/api.js';
import { createStaffSession } from '../src/staff.js';
import { createReportPage } from '../src/report.js';
import { municipalReport } from './fixtures.js';

let staff, page;
beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  page?.destroy();
  staff?.destroy();
  page = staff = null;
  document.body.replaceChildren();
  delete window.HTMLDialogElement.prototype.showModal;
  delete window.HTMLDialogElement.prototype.close;
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

it('loads staff images with a header and revokes the temporary URL when the owning view closes', async () => {
  const create = vi.fn(() => 'blob:synthetic-photo');
  const revoke = vi.fn();
  vi.stubGlobal(
    'URL',
    class extends URL {
      static createObjectURL = create;
      static revokeObjectURL = revoke;
    },
  );
  const controller = new AbortController();
  staff = createStaffSession();
  staff.setToken('synthetic-staff-token-for-photo-tests');
  const fetchImpl = vi.fn(
    async () =>
      new Response('synthetic-image-body', {
        headers: { 'Content-Type': 'image/jpeg' },
      }),
  );
  const image = createPhoto(municipalReport(), {
    api: createApiClient({ staff, fetchImpl }),
    signal: controller.signal,
  });
  document.body.append(image);
  expect(image.getAttribute('src')).toBeNull();
  await vi.advanceTimersByTimeAsync(0);
  expect(image.getAttribute('src')).toBe('blob:synthetic-photo');
  expect(fetchImpl.mock.calls[0][1].headers['X-Staff-Token']).toBe(
    staff.getToken(),
  );
  expect(fetchImpl.mock.calls[0][1].headers.Accept).toBe(
    'image/jpeg, image/png',
  );
  controller.abort();
  expect(revoke).toHaveBeenCalledWith('blob:synthetic-photo');
});

it('rejects unsafe photos, invalid MIME and stale image responses without creating an object URL', async () => {
  const create = vi.fn();
  vi.stubGlobal(
    'URL',
    class extends URL {
      static createObjectURL = create;
      static revokeObjectURL = vi.fn();
    },
  );
  staff = createStaffSession();
  staff.setToken('synthetic-staff-token-for-photo-tests');
  const fetchImpl = vi.fn(
    async () =>
      new Response('<svg onload=bad>', {
        headers: { 'Content-Type': 'image/svg+xml' },
      }),
  );
  const api = createApiClient({ staff, fetchImpl });
  expect(
    createPhoto(municipalReport({ photo_url: 'https://tracker.test/image' }), {
      api,
    }).tagName,
  ).toBe('P');
  expect(fetchImpl).not.toHaveBeenCalled();
  const image = createPhoto(municipalReport(), {
    api,
    signal: new AbortController().signal,
  });
  document.body.append(image);
  await vi.advanceTimersByTimeAsync(0);
  expect(create).not.toHaveBeenCalled();
  expect(document.body.textContent).toContain('Foto no disponible');
  let resolve;
  fetchImpl.mockImplementation(
    () =>
      new Promise((r) => {
        resolve = r;
      }),
  );
  const controller = new AbortController();
  createPhoto(municipalReport(), { api, signal: controller.signal });
  controller.abort();
  resolve(
    new Response('synthetic', { headers: { 'Content-Type': 'image/jpeg' } }),
  );
  await vi.advanceTimersByTimeAsync(0);
  expect(create).not.toHaveBeenCalled();
});

it('provides a modal photo enlargement with a close button and keyboard focus restoration', async () => {
  Object.defineProperty(window.HTMLDialogElement.prototype, 'showModal', {
    configurable: true,
    value: function () {
      this.open = true;
    },
  });
  Object.defineProperty(window.HTMLDialogElement.prototype, 'close', {
    configurable: true,
    value: function () {
      this.open = false;
    },
  });
  const root = document.createElement('section');
  document.body.append(root);
  page = createReportPage(root, {
    id: municipalReport().id,
    api: { getReport: vi.fn(async () => municipalReport()) },
    mapFactory: () => ({ destroy() {} }),
  });
  await vi.advanceTimersByTimeAsync(0);
  root.querySelector('.report-photo').dispatchEvent(new window.Event('load'));
  const button = root.querySelector('.zoom-photo');
  button.focus();
  button.click();
  const dialog = root.querySelector('dialog');
  expect(dialog.open).toBe(true);
  expect(dialog.querySelector('img').alt).toContain('Bache');
  dialog.querySelector('button').click();
  expect(dialog.open).toBe(false);
  expect(document.activeElement).toBe(button);
});
