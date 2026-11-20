import { element } from './dom.js';

/** Dismissal exists in memory only; no identity, cookies or browser storage. */
export function createStaffHelp() {
  const button = element('button', 'help-button', '?');
  button.type = 'button';
  button.title = 'Guía rápida';
  button.setAttribute('aria-label', 'Guía rápida para el equipo');
  button.setAttribute('aria-expanded', 'false');
  button.setAttribute('aria-controls', 'staff-guide');
  const guide = element('aside', 'staff-guide');
  guide.id = 'staff-guide';
  guide.hidden = true;
  guide.setAttribute('aria-labelledby', 'staff-guide-title');
  const title = element('h2', '', 'Guía rápida');
  title.id = 'staff-guide-title';
  title.tabIndex = -1;
  const steps = element('ol');
  for (const text of [
    'Mapa: filtra y selecciona un reporte para ver su foto y verificación.',
    'Triaje: entra en Modo personal para asignar y atender los casos pendientes.',
    'Reporte: registra avances y notas; el historial conserva cada cambio. Panel: consulta indicadores y exporta CSV.',
  ])
    steps.append(element('li', '', text));
  const dismiss = element('button', '', 'Entendido');
  dismiss.type = 'button';
  let introduced = false;
  const close = () => {
    guide.hidden = true;
    button.setAttribute('aria-expanded', 'false');
    button.focus();
  };
  const open = (focus = true) => {
    introduced = true;
    guide.hidden = false;
    button.setAttribute('aria-expanded', 'true');
    if (focus) title.focus();
  };
  button.addEventListener('click', () => (guide.hidden ? open() : close()));
  dismiss.addEventListener('click', close);
  guide.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.stopPropagation();
      close();
    }
  });
  guide.append(title, steps, dismiss);
  return {
    button,
    guide,
    introduce() {
      if (!introduced) open(false);
    },
  };
}
