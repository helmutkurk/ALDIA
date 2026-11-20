/** Stable mirror of documentation/api-contract.md. Keep labels in sync. */
export const CATEGORIES = Object.freeze(
  [
    { id: 'accessibility', label: 'Accesibilidad (rampas, bordillos)' },
    { id: 'sidewalk', label: 'Acera en mal estado' },
    { id: 'pothole', label: 'Bache' },
    { id: 'graffiti', label: 'Grafiti' },
    { id: 'open_drain', label: 'Alcantarilla abierta' },
    { id: 'street_light', label: 'Luminaria dañada' },
  ].map(Object.freeze),
);

/** @param {string} id */
export function categoryLabel(id) {
  return CATEGORIES.find((category) => category.id === id)?.label ?? id;
}

/** Decorative category glyphs; labels beside them carry the meaning. */
export function categoryIcon(id) {
  const paths = {
    accessibility: 'M14 4h.01M12 8v5h5l3 6M12 10H8M9 13a5 5 0 1 0 6 6',
    sidewalk: 'M3 7h18M3 17h18M7 7v10M12 7l-2 5 4 2-1 3M18 7v10',
    pothole: 'M3 8l5-2 4 3 5-2 4 2M3 17l5 2 5-2 5 1 3-2M7 12l3 3 6-3',
    graffiti: 'M4 4h16v16H4zM7 16l3-8 3 8M8 13h4M15 8v8h3',
    open_drain: 'M3 7h18v12H3zM6 10l12 6M10 10l8 4M6 14l4 2M3 4h18',
    street_light:
      'M9 21V7a4 4 0 0 1 8 0M14 8h6l-1-3h-4zM6 21h6M16 11v3M20 11l1 2',
  };
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  for (const [key, value] of Object.entries({
    viewBox: '0 0 24 24',
    class: 'category-icon',
    'aria-hidden': 'true',
    fill: 'none',
    stroke: 'currentColor',
    'stroke-width': '1.5',
    'stroke-linecap': 'round',
    'stroke-linejoin': 'round',
  }))
    svg.setAttribute(key, value);
  const path = document.createElementNS(svg.namespaceURI, 'path');
  path.setAttribute('d', paths[id] ?? 'M4 4h16v16H4z');
  svg.append(path);
  return svg;
}
