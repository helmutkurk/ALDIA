import { element } from './dom.js';
import { t } from './i18n.js';

export const number = new Intl.NumberFormat('es-GT', {
  maximumFractionDigits: 1,
});
/** Null metrics are deliberately not rendered as zero. @param {number|null} value */
export const quantity = (value) =>
  value === null || value === undefined
    ? t.dash.unavailable
    : number.format(value);
/** @param {number|null} value */
const percent = (value) =>
  value === null || value === undefined
    ? t.dash.unavailable
    : `${number.format(value * 100)} %`;

/** @param {object} stats */
export function metricCards(stats, headline = false, listLink) {
  const cards = element('dl', 'metric-cards');
  /** @param {string} key @param {string} value @param {number} [n] @param {object} [patch] */
  function card(key, value, n, patch) {
    const wrapper = element('div', 'metric-card');
    const label = element('dt', '', t.dash[key]);
    const data = element('dd');
    data.append(patch ? listLink(value, patch) : element('span', '', value));
    if (n !== null && n !== undefined)
      data.append(element('small', '', t.dash.sample(n)));
    wrapper.append(label, data);
    cards.append(wrapper);
  }
  if (headline) cards.classList.add('kpi-strip');
  cards.setAttribute(
    'aria-label',
    headline ? t.dash.kpiStrip : t.dash.indicators,
  );
  for (const key of headline
    ? [
        'recibidos',
        'rechazados_verificador',
        'abiertos',
        'resueltos',
        'cerrados_sin_solucion',
      ]
    : []) {
    card(
      key,
      quantity(stats[key]),
      undefined,
      key === 'rechazados_verificador'
        ? { state: 'rechazado_verificador', state_group: '' }
        : undefined,
    );
  }
  if (headline) return cards;
  const denominator =
    stats.recibidos -
    (stats.by_state.duplicado ?? 0) -
    (stats.by_state.fuera_de_competencia ?? 0);
  card(
    'tasa_resolucion',
    percent(stats.tasa_resolucion),
    Math.max(0, denominator),
  );
  for (const key of ['median', 'p90', 'mean']) {
    card(
      key,
      stats.resolucion_horas[key] === null
        ? t.dash.unavailable
        : `${quantity(stats.resolucion_horas[key])} ${t.dash.hours}`,
      stats.resolucion_horas.n,
    );
  }
  for (const [key, field] of [
    ['first', 'median'],
    ['firstP90', 'p90'],
  ]) {
    card(
      key,
      stats.primera_respuesta_horas[field] === null
        ? t.dash.unavailable
        : `${quantity(stats.primera_respuesta_horas[field])} ${t.dash.hours}`,
      stats.primera_respuesta_horas.n,
    );
  }
  card('sla_cumplido', percent(stats.sla_cumplido), stats.resolucion_horas.n);
  card('vencidos', quantity(stats.vencidos));
  return cards;
}
