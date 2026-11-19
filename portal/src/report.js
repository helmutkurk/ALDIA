import { createLocationMap } from './map.js';
import { createReportDetails, element } from './panel.js';
import { createStaffActions } from './actions.js';
import { filtersHash } from './filters.js';
import { reportState, stateLabel } from './states.js';
import { createPhoto } from './photo.js';
import { categoryLabel } from './categories.js';
import { ui, staffError, formatDate, t } from './i18n.js';

/** Standalone, cancellable report view. Report strings are never interpreted as HTML.
 * @param {HTMLElement} root
 * @param {{id: string, api: object, mapFactory?: typeof createLocationMap, staff?: object, filters?: object, getAdjacent?: Function, onChanged?: () => void}} options
 */
export function createReportPage(
  root,
  {
    id,
    api,
    mapFactory = createLocationMap,
    staff,
    filters = {},
    getAdjacent,
    onChanged = () => {},
  },
) {
  let controller;
  let map;
  let generation = 0;
  let actions;
  let dialog;
  const back = element('a', 'back-link', t.backToMap);
  back.href = filtersHash('#/', filters);
  async function load() {
    controller?.abort();
    actions?.destroy();
    dialog?.remove();
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
      const details = createReportDetails(report, {
        api,
        signal: controller.signal,
      });
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
      const navigation = element('nav', 'report-navigation');
      if (getAdjacent) {
        for (const [direction, label] of [
          [-1, ui.previous],
          [1, ui.next],
        ]) {
          const button = element('button', '', label);
          button.type = 'button';
          button.addEventListener('click', async () => {
            navigation.querySelectorAll('button').forEach((control) => {
              control.disabled = true;
            });
            try {
              const nextId = await getAdjacent(
                id,
                direction,
                controller.signal,
              );
              if (current === generation && nextId)
                window.location.hash = filtersHash(
                  `#/reports/${nextId}`,
                  filters,
                );
            } catch (error) {
              if (current === generation)
                details.append(element('p', '', staffError(error)));
            } finally {
              if (current === generation)
                navigation.querySelectorAll('button').forEach((control) => {
                  control.disabled = false;
                });
            }
          });
          navigation.append(button);
        }
      }
      const metadata = element('dl', 'report-metadata');
      for (const [label, value] of [
        [ui.created, formatDate(report.created_at)],
        [
          ui.verified,
          report.verified_at ? formatDate(report.verified_at) : t.unknownDate,
        ],
        [
          ui.changed,
          report.state_changed_at
            ? formatDate(report.state_changed_at)
            : t.unknownDate,
        ],
        [ui.assignee, report.assignee ?? ui.unassigned],
        [ui.coordinates, `${report.latitude}, ${report.longitude}`],
      ])
        metadata.append(element('dt', '', label), element('dd', '', value));
      const timeline = element('section', 'timeline');
      timeline.append(element('h2', '', ui.timeline));
      const events = element('ol');
      for (const event of report.events ?? []) {
        const item = element('li');
        item.append(
          element(
            'p',
            '',
            `${formatDate(event.at)} · ${ui.actors[event.actor_role] ?? event.actor_role} · ${event.from_state ? stateLabel(event.from_state) + ' → ' : ''}${stateLabel(event.to_state)}`,
          ),
        );
        if (event.public_note) item.append(element('p', '', event.public_note));
        if (staff?.getToken() && event.internal_note)
          item.append(
            element('p', '', `${ui.internalNote}: ${event.internal_note}`),
          );
        events.append(item);
      }
      timeline.append(
        events.children.length ? events : element('p', '', ui.noEvents),
      );
      const controls = element('section', 'staff-actions');
      actions = createStaffActions(controls, {
        report,
        api,
        staff,
        onSaved: () => {
          onChanged();
          load();
        },
      });
      root.replaceChildren(
        back,
        navigation,
        details,
        metadata,
        timeline,
        controls,
        location,
      );
      const photo = details.querySelector('img');
      if (photo) {
        const zoom = element('button', 'zoom-photo', ui.zoomPhoto);
        zoom.type = 'button';
        zoom.disabled = !(photo.complete && photo.currentSrc);
        photo.addEventListener('load', () => {
          zoom.disabled = false;
        });
        photo.addEventListener('error', () => {
          zoom.disabled = true;
        });
        photo.after(zoom);
        zoom.addEventListener('click', () => {
          dialog?.remove();
          dialog = element('dialog', 'photo-dialog');
          dialog.setAttribute('aria-label', ui.zoomPhoto);
          const image = photo.cloneNode();
          image.loading = 'eager';
          const close = element('button', '', ui.closePhoto);
          close.type = 'button';
          close.addEventListener('click', () => {
            dialog.close();
            zoom.focus();
          });
          dialog.append(close, image);
          root.append(dialog);
          dialog.showModal();
        });
      }
      if (api.getNearby) {
        const nearby = element('section', 'nearby-reports');
        nearby.append(
          element('h2', '', ui.nearby),
          element('p', '', t.loading),
        );
        root.append(nearby);
        api
          .getNearby(id, { signal: controller.signal })
          .then((items) => {
            if (current !== generation) return;
            nearby.replaceChildren(element('h2', '', ui.nearby));
            if (!items.length) nearby.append(element('p', '', ui.noNearby));
            for (const candidate of items) {
              const item = element('article');
              const link = element('a', '', categoryLabel(candidate.category));
              link.href = filtersHash(`#/reports/${candidate.id}`, filters);
              item.append(link);
              item.append(
                createPhoto(candidate, {
                  api,
                  signal: controller.signal,
                  thumbnail: true,
                }),
              );
              if (staff?.getToken()) {
                const mark = element('button', '', ui.markDuplicate);
                mark.type = 'button';
                mark.disabled = reportState(report) !== 'en_revision';
                if (mark.disabled)
                  item.append(element('p', 'muted', ui.duplicateHelp));
                mark.addEventListener('click', () => {
                  actions.destroy();
                  actions = createStaffActions(controls, {
                    report,
                    api,
                    staff,
                    onSaved: () => {
                      onChanged();
                      load();
                    },
                    duplicateOf: candidate.id,
                  });
                  controls.querySelector('select')?.focus();
                });
                item.append(mark);
              }
              nearby.append(item);
            }
          })
          .catch((error) => {
            if (current === generation && error.name !== 'AbortError')
              nearby.replaceChildren(
                element('h2', '', ui.nearby),
                element('p', '', ui.nearbyError),
              );
          });
      }
      map = mapFactory(mapElement, report, { api, signal: controller.signal });
      title.focus({ preventScroll: true });
    } catch (error) {
      if (current !== generation || error.name === 'AbortError') return;
      const message = element(
        'p',
        'error-message',
        error.status === 404
          ? t.reportNotFound
          : [401, 403, 409, 503].includes(error.status)
            ? staffError(error)
            : t.reportError,
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
      actions?.destroy();
      dialog?.remove();
      controller?.abort();
      map?.destroy();
      map = null;
      root.replaceChildren();
      root.removeAttribute('aria-busy');
    },
  };
}
