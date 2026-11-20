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
      empty.className = 'thumb-missing';
      empty.setAttribute('aria-hidden', 'true');
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
  image.loading = 'lazy';
  image.decoding = 'async';
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
