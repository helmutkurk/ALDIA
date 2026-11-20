import { safePhotoUrl } from './api.js';
import { categoryLabel } from './categories.js';
import { t } from './i18n.js';

/** Safe image element. Staff images use authenticated fetch; object URLs live only
 * until the owning view is cancelled so modal clones remain usable meanwhile.
 * @param {object} report @param {{api?: object, signal?: AbortSignal, thumbnail?: boolean, className?: string, quiet?: boolean}} [options]
 */
export function createPhoto(
  report,
  { api, signal, thumbnail = false, className, quiet = false } = {},
) {
  const fallback = () => {
    if (quiet) {
      const empty = document.createElement('span');
      empty.className = `${className ?? 'nearby-thumbnail'} thumb-missing`;
      const icon = document.createElementNS(
        'http://www.w3.org/2000/svg',
        'svg',
      );
      icon.setAttribute('viewBox', '0 0 24 24');
      icon.setAttribute('aria-hidden', 'true');
      icon.setAttribute('fill', 'none');
      icon.setAttribute('stroke', 'currentColor');
      const path = document.createElementNS(icon.namespaceURI, 'path');
      path.setAttribute('d', 'M3 3l18 18M4 8v12h16v-3M8 4h12v9M4 17l5-5 4 4');
      icon.append(path);
      empty.append(icon, document.createTextNode('sin foto'));
      return empty;
    }
    const message = document.createElement('p');
    message.className = 'muted';
    message.textContent = t.photoUnavailable;
    return message;
  };
  let url = safePhotoUrl(
    thumbnail ? (report.thumbnail_url ?? report.photo_url) : report.photo_url,
  );
  if (!url) return fallback();
  if (thumbnail) url = url.replace(/\/photo$/, '/thumbnail');
  const image = document.createElement('img');
  image.className =
    className ?? (thumbnail ? 'nearby-thumbnail' : 'report-photo');
  // A quiet thumbnail repeats text the row already carries, so it is decorative.
  image.alt = quiet ? '' : t.photoAlt(categoryLabel(report.category));
  image.setAttribute('loading', 'lazy');
  image.decoding = 'async';
  if (className === 'row-thumbnail') image.width = image.height = 72;
  let objectUrl;
  const revoke = () => {
    if (objectUrl) {
      URL.revokeObjectURL(objectUrl);
      objectUrl = null;
    }
  };
  image.addEventListener(
    'error',
    () => {
      revoke();
      image.replaceWith(fallback());
    },
    { once: true },
  );
  if (api?.hasStaff?.()) {
    if (signal?.aborted) return fallback();
    api
      .getPhotoBlob(url, { signal })
      .then((blob) => {
        if (signal?.aborted) return;
        objectUrl = URL.createObjectURL(blob);
        image.src = objectUrl;
        signal?.addEventListener('abort', revoke, { once: true });
      })
      .catch((error) => {
        if (error.name !== 'AbortError' && !signal?.aborted)
          image.replaceWith(fallback());
      });
  } else image.src = url;
  return image;
}
