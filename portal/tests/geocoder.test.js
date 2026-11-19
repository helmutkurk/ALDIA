import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createPlaceSearch } from '../src/geocoder.js';

let search;
beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  search?.destroy();
  document.body.replaceChildren();
  vi.useRealTimers();
});
function setup(
  fetchImpl = vi
    .fn()
    .mockResolvedValue(
      new Response(
        JSON.stringify([
          { display_name: '<b>Guatemala</b>', lat: '14.6', lon: '-90.5' },
        ]),
      ),
    ),
) {
  const root = document.createElement('div');
  document.body.append(root);
  const onSelect = vi.fn();
  search = createPlaceSearch(root, { onSelect, fetchImpl });
  const input = root.querySelector('input');
  const submit = () =>
    root
      .querySelector('form')
      .dispatchEvent(new window.Event('submit', { cancelable: true }));
  return { root, input, submit, fetchImpl, onSelect };
}

describe('place search', () => {
  it('requires explicit search, debounces 500 ms, uses required parameters and identifying referrer', async () => {
    const { root, input, submit, fetchImpl, onSelect } = setup();
    input.value = 'Guatemala';
    input.dispatchEvent(new window.Event('input'));
    await vi.advanceTimersByTimeAsync(1000);
    expect(fetchImpl).not.toHaveBeenCalled();
    submit();
    await vi.advanceTimersByTimeAsync(499);
    submit();
    await vi.advanceTimersByTimeAsync(499);
    expect(fetchImpl).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(fetchImpl).toHaveBeenCalledOnce();
    const [url, options] = fetchImpl.mock.calls[0];
    expect(Object.fromEntries(new URL(url).searchParams)).toEqual({
      format: 'json',
      limit: '5',
      countrycodes: 'gt,co,mx',
      q: 'Guatemala',
    });
    expect(options.referrerPolicy).toBe('strict-origin-when-cross-origin');
    expect(options.headers['User-Agent']).toBeUndefined();
    const result = root.querySelector('.place-results button');
    expect(result.textContent).toBe('<b>Guatemala</b>');
    expect(result.querySelector('b')).toBeNull();
    input.dispatchEvent(
      new window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }),
    );
    expect(document.activeElement).toBe(result);
    result.click();
    expect(onSelect).toHaveBeenCalledWith({
      latitude: 14.6,
      longitude: -90.5,
      label: '<b>Guatemala</b>',
    });
  });
  it('spaces requests by at least one second and caches repeated queries', async () => {
    const fetchImpl = vi
      .fn()
      .mockImplementation(async () => new Response('[]'));
    const { input, submit } = setup(fetchImpl);
    input.value = 'Ciudad';
    submit();
    await vi.advanceTimersByTimeAsync(500);
    input.value = 'Antigua';
    submit();
    await vi.advanceTimersByTimeAsync(999);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    input.value = 'Ciudad';
    submit();
    await vi.advanceTimersByTimeAsync(1000);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
  it('cancels work on edit and teardown and reports network failures', async () => {
    const { root, input, submit, fetchImpl } = setup(
      vi.fn().mockRejectedValue(new TypeError('offline')),
    );
    input.value = 'Ciudad';
    submit();
    input.dispatchEvent(new window.Event('input'));
    await vi.advanceTimersByTimeAsync(1000);
    expect(fetchImpl).not.toHaveBeenCalled();
    submit();
    await vi.advanceTimersByTimeAsync(500);
    expect(root.textContent).toContain('No se pudo buscar');
    submit();
    search.destroy();
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});

it('ignores late results after editing, handles malformed data and honors a custom endpoint', async () => {
  let resolve;
  const fetchImpl = vi
    .fn()
    .mockImplementationOnce(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    )
    .mockResolvedValueOnce(
      new Response('[{"display_name":"bad","lat":"999","lon":"0"}]'),
    );
  const { input, submit, root } = setup(fetchImpl);
  input.value = 'Ciudad';
  submit();
  await vi.advanceTimersByTimeAsync(500);
  const signal = fetchImpl.mock.calls[0][1].signal;
  input.value = 'Otro lugar';
  input.dispatchEvent(new window.Event('input'));
  expect(signal.aborted).toBe(true);
  resolve(new Response('[{"display_name":"Old","lat":"14","lon":"-90"}]'));
  await Promise.resolve();
  await Promise.resolve();
  expect(root.querySelector('.place-results button')).toBeNull();
  submit();
  await vi.advanceTimersByTimeAsync(1000);
  expect(root.textContent).toContain('No se pudo buscar');
  search.destroy();
  const customFetch = vi.fn().mockResolvedValue(new Response('[]'));
  search = createPlaceSearch(root, {
    onSelect: vi.fn(),
    endpoint: '/geocoder/search',
    fetchImpl: customFetch,
  });
  root.querySelector('input').value = 'Antigua';
  root
    .querySelector('form')
    .dispatchEvent(new window.Event('submit', { cancelable: true }));
  await vi.advanceTimersByTimeAsync(500);
  expect(new URL(customFetch.mock.calls[0][0]).pathname).toBe(
    '/geocoder/search',
  );
  expect(root.textContent).toContain('No se encontraron lugares');
});
