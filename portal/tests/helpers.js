// Builders for test data. Coordinates are synthetic points in Guatemala City.

export const NOW = Date.parse("2026-11-19T18:00:00Z");
export const DAY = 86_400_000;

let seq = 0;
export function report(overrides = {}) {
  seq += 1;
  return {
    id: `rep_${seq}`,
    kind: "report",
    category: "pothole",
    lat: 14.6405,
    lng: -90.5135,
    createdAt: new Date(NOW - 2 * DAY).toISOString(),
    severity: "damages_cars",
    reporterId: `vec_${seq}`,
    verification: { status: "passed", confidence: 0.9 },
    photoUrl: "https://example.org/a.jpg",
    ...overrides,
  };
}

export function rawCase(overrides = {}) {
  return {
    id: "ALD-GT-00001",
    category: "pothole",
    status: "new",
    lat: 14.6405,
    lng: -90.5135,
    address: "6a. Avenida y 12 Calle, Zona 1",
    zone: "Zona 1",
    reports: [report()],
    history: [{ status: "new", at: new Date(NOW - 2 * DAY).toISOString(), by: "sistema" }],
    ...overrides,
  };
}
