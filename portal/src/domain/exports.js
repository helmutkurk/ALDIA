// Exports for governments: GeoJSON (any GIS tool, Google My Maps, QGIS) and Open311 GeoReport v2
// service requests, the standard most city reporting systems (FixMyStreet, SeeClickFix, 311s) speak.

import { categoryLabel } from "./categories.js";
import { statusGroup, statusLabel } from "./statuses.js";

/** One case as an Open311 GeoReport v2 service request. Reporter identities are never exported. */
export function toOpen311(c, { agency = "" } = {}) {
  const lastNote = [...c.history].reverse().find((h) => h.note)?.note;
  return {
    service_request_id: c.id,
    status: statusGroup(c.status) === "open" ? "open" : "closed",
    status_notes: lastNote ?? statusLabel(c.status),
    service_name: categoryLabel(c.category),
    service_code: c.category,
    description: `${categoryLabel(c.category)}. ${c.reporterCount} vecino(s) lo reportaron.`,
    agency_responsible: agency,
    requested_datetime: c.firstReportedAt,
    updated_datetime: c.lastActivityAt,
    address: c.address ?? "",
    lat: c.lat,
    long: c.lng,
    media_url: c.beforePhotoUrl?.startsWith("data:") ? "" : (c.beforePhotoUrl ?? ""),
  };
}

export function toGeoJSON(cases) {
  return {
    type: "FeatureCollection",
    features: cases.map((c) => ({
      type: "Feature",
      geometry: { type: "Point", coordinates: [c.lng, c.lat] },
      properties: {
        id: c.id,
        category: c.category,
        category_label: categoryLabel(c.category),
        status: c.status,
        status_label: statusLabel(c.status),
        severity: c.severity,
        reporters: c.reporterCount,
        priority: c.priority,
        overdue: c.overdue,
        first_reported_at: c.firstReportedAt,
        address: c.address ?? "",
        zone: c.zone ?? "",
      },
    })),
  };
}
