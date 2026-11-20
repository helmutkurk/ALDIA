import { element } from './dom.js';
import { lastWeekSection } from './dashboard-trends.js';
import { t } from './i18n.js';

/** Seven calendar days, inclusive, in the municipality's timezone (not the staff device timezone). */
export function recentDates(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Guatemala',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const part = (type) => parts.find((part) => part.type === type).value;
  const end = `${part('year')}-${part('month')}-${part('day')}`;
  const start = new Date(`${end}T12:00:00Z`);
  start.setUTCDate(start.getUTCDate() - 6);
  return { created_from: start.toISOString().slice(0, 10), created_to: end };
}

/** This request has its own dates; it retains the area/category/staff filters.
 * Sparklines use the weekly buckets returned for these seven days, never invented daily counts. */
export function recentActivity({ api, filters, signal }) {
  const root = element('section', 'last-week dash-block');
  const dates = recentDates();
  async function load() {
    root.setAttribute('aria-busy', 'true');
    const loading = element('p', 'muted', t.dashboardLoading);
    loading.setAttribute('role', 'status');
    root.replaceChildren(element('h2', '', 'Últimos 7 días'), loading);
    try {
      const stats = await api.getStats(
        { ...filters, ...dates, include_old: true },
        { signal },
      );
      if (signal.aborted) return;
      const content = lastWeekSection(stats.weekly, {
        title: 'Últimos 7 días',
        totals: stats,
        note: `${dates.created_from} a ${dates.created_to} · Hora de Guatemala. Tendencia agrupada por semana dentro de estos siete días.`,
      });
      root.replaceChildren(...content.childNodes);
    } catch (error) {
      if (signal.aborted || error.name === 'AbortError') return;
      const retry = element('button', 'retry-button', t.retry);
      retry.type = 'button';
      retry.addEventListener('click', load);
      root.replaceChildren(
        element('h2', '', 'Últimos 7 días'),
        element('p', 'muted', 'No se pudo cargar la actividad reciente.'),
        retry,
      );
    } finally {
      if (!signal.aborted) root.setAttribute('aria-busy', 'false');
    }
  }
  load();
  return root;
}
