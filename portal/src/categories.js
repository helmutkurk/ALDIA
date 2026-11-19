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
