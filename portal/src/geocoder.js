import { element } from './panel.js';
import { t } from './i18n.js';

const GEOCODER_URL =
  import.meta.env.VITE_GEOCODER_URL ??
  'https://nominatim.openstreetmap.org/search';

/** @typedef {{latitude: number, longitude: number, label: string}} Place */
/** Explicit searches only: public Nominatim forbids search-as-you-type.
 * Requests debounce 500 ms and start at least 1000 ms apart in this instance.
 * @param {HTMLElement} root
 * @param {{onSelect: (place: Place) => void, endpoint?: string, fetchImpl?: typeof fetch}} options
 */
export function createPlaceSearch(
  root,
  { onSelect, endpoint = GEOCODER_URL, fetchImpl = globalThis.fetch },
) {
  const base = new URL(endpoint, window.location.origin);
  if (
    !['http:', 'https:'].includes(base.protocol) ||
    base.username ||
    base.password ||
    base.hash
  )
    throw new TypeError(
      'Geocoder URL must be HTTP(S), without credentials or fragment.',
    );
  const form = element('form', 'place-search');
  form.setAttribute('role', 'search');
  const label = element('label', '', t.placeSearch);
  label.htmlFor = 'place-query';
  const input = document.createElement('input');
  input.id = 'place-query';
  input.type = 'search';
  input.autocomplete = 'off';
  input.required = true;
  input.maxLength = 200;
  input.placeholder = t.placePlaceholder;
  input.setAttribute('aria-describedby', 'place-help place-status');
  const button = element('button', 'search-button', t.search);
  button.type = 'submit';
  const controls = element('div', 'search-controls');
  controls.append(input, button);
  const help = element('p', 'muted', t.searchHelp);
  help.id = 'place-help';
  const status = element('p', 'search-status');
  status.id = 'place-status';
  status.setAttribute('role', 'status');
  const results = element('ul', 'place-results');
  results.setAttribute('aria-label', t.placeResults);
  const attribution = element('a', 'search-attribution', t.searchAttribution);
  attribution.href = 'https://www.openstreetmap.org/copyright';
  form.append(label, controls, help, status, results, attribution);
  root.replaceChildren(form);
  let timer;
  let deadline;
  let controller;
  let lastStart = -Infinity;
  let generation = 0;
  const cache = new Map();
  /** Cancel pending searches without triggering any automatic request. */
  function cancel() {
    generation++;
    clearTimeout(timer);
    clearTimeout(deadline);
    controller?.abort();
    results.replaceChildren();
    status.textContent = '';
  }
  /** @param {Place[]} places */
  function render(places) {
    results.replaceChildren();
    status.textContent = places.length
      ? t.placeCount(places.length)
      : t.searchEmpty;
    for (const place of places) {
      const item = element('li');
      const choice = element('button', '', place.label);
      choice.type = 'button';
      choice.addEventListener('click', () => {
        cancel();
        input.value = place.label;
        input.focus();
        onSelect(place);
      });
      item.append(choice);
      results.append(item);
    }
  }
  /** @param {SubmitEvent} event */
  function submit(event) {
    event.preventDefault();
    cancel();
    const query = input.value.trim();
    if (!query) return;
    const current = generation;
    const delay = cache.has(query)
      ? 500
      : Math.max(500, lastStart + 1000 - Date.now());
    status.textContent = t.searchLoading;
    timer = setTimeout(async () => {
      if (cache.has(query)) {
        render(cache.get(query));
        return;
      }
      lastStart = Date.now();
      controller = new AbortController();
      const requestController = controller;
      deadline = setTimeout(() => requestController.abort(), 15000);
      const url = new URL(base);
      url.searchParams.set('format', 'json');
      url.searchParams.set('limit', '5');
      url.searchParams.set('countrycodes', 'gt,co,mx');
      url.searchParams.set('q', query);
      try {
        const response = await fetchImpl(url.href, {
          signal: requestController.signal,
          headers: { Accept: 'application/json' },
          credentials: 'omit',
          // Browsers supply User-Agent and an origin Referer identifying this site.
          referrerPolicy: 'strict-origin-when-cross-origin',
        });
        if (!response.ok) throw new Error('Geocoder request failed.');
        const body = await response.json();
        if (current !== generation) return;
        if (requestController.signal.aborted)
          throw requestController.signal.reason;
        if (
          !Array.isArray(body) ||
          body.length > 5 ||
          !body.every(
            (item) =>
              item &&
              typeof item.display_name === 'string' &&
              item.display_name.trim() &&
              typeof item.lat === 'string' &&
              item.lat.trim() &&
              typeof item.lon === 'string' &&
              item.lon.trim() &&
              Number.isFinite(Number(item.lat)) &&
              Math.abs(Number(item.lat)) <= 90 &&
              Number.isFinite(Number(item.lon)) &&
              Math.abs(Number(item.lon)) <= 180,
          )
        )
          throw new Error('Invalid geocoder response.');
        const places = body.map((item) => ({
          label: item.display_name,
          latitude: Number(item.lat),
          longitude: Number(item.lon),
        }));
        if (cache.size >= 100) cache.delete(cache.keys().next().value);
        cache.set(query, places);
        render(places);
      } catch {
        if (current === generation) status.textContent = t.searchError;
      } finally {
        if (current === generation) clearTimeout(deadline);
      }
    }, delay);
  }
  /** Native buttons support Enter/Space and Tab; arrows provide list navigation.
   * @param {KeyboardEvent} event
   */
  function onKeyDown(event) {
    const choices = [...results.querySelectorAll('button')];
    const index = choices.indexOf(document.activeElement);
    if (event.key === 'Escape') {
      cancel();
      input.focus();
      return;
    }
    if (!choices.length) return;
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      choices[(index + 1) % choices.length].focus();
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      if (index <= 0) input.focus();
      else choices[index - 1].focus();
    }
  }
  form.addEventListener('submit', submit);
  form.addEventListener('keydown', onKeyDown);
  input.addEventListener('input', cancel);
  return {
    cancel,
    destroy() {
      cancel();
      form.removeEventListener('submit', submit);
      form.removeEventListener('keydown', onKeyDown);
      input.removeEventListener('input', cancel);
      root.replaceChildren();
    },
  };
}
