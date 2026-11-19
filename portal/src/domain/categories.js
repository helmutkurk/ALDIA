// Report categories shown in the portal. P1 list from the 2026-11-19 kick-off proposals.
// Ids are stable and shared with the app and the backend; labels are Guatemalan Spanish.

export const CATEGORIES = Object.freeze([
  { id: "pothole", label: "Bache" },
  { id: "sidewalk", label: "Banqueta dañada" },
  { id: "ramp", label: "Rampa dañada u obstruida" },
  { id: "street_light", label: "Luminaria apagada" },
  { id: "drain_cover", label: "Alcantarilla sin tapa" },
  { id: "signage", label: "Señalización dañada" },
]);

export const CATEGORY_IDS = new Set(CATEGORIES.map((c) => c.id));

export function categoryLabel(id) {
  return CATEGORIES.find((c) => c.id === id)?.label ?? "Otro";
}
