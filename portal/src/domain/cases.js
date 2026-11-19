// Turns parsed cases into what the portal shows: how many independent people reported it, how
// credible it is, its photos, age and priority. Also groups loose reports into cases for a backend
// that does not group them yet (same category within a radius, like FixMyStreet's "nearby" check).

import { distanceM } from "./geo.js";
import { isOpen } from "./statuses.js";
import { priorityScore, isOverdue } from "./priority.js";

export const DUPLICATE_RADIUS_M = 20;
const DAY_MS = 86_400_000;
const SEVERITY_RANK = { minor: 0, damages_cars: 1, dangerous: 2 };

/**
 * Credibility from independent people, not from photo count (one person reporting five times
 * counts once). Only reports whose photo passed the verifier count.
 *   pending:      no verified photo yet
 *   single:       one person
 *   corroborated: two or more independent people
 */
export function credibility(reports) {
  const people = new Set(
    reports.filter((r) => r.verification.status === "passed" && r.kind !== "repair_check").map((r) => r.reporterId),
  );
  if (people.size === 0) return { level: "pending", people: 0 };
  if (people.size === 1) return { level: "single", people: 1 };
  return { level: "corroborated", people: people.size };
}

export const CREDIBILITY_LABELS = Object.freeze({
  pending: "Foto en revisión",
  single: "Sin corroborar",
  corroborated: "Corroborado",
});

/** Adds the derived fields the views need. `now` is a millisecond timestamp. */
export function summarizeCase(c, now) {
  const reports = [...c.reports].sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
  const problemReports = reports.filter((r) => r.kind !== "repair_check");
  const first = problemReports[0] ?? reports[0];
  const last = reports[reports.length - 1];
  const severity = problemReports.reduce(
    (worst, r) => (SEVERITY_RANK[r.severity] > SEVERITY_RANK[worst] ? r.severity : worst),
    "minor",
  );
  const cred = credibility(reports);
  const before = problemReports.find((r) => r.verification.status === "passed" && r.photoUrl);
  const after = [...reports]
    .reverse()
    .find((r) => r.kind === "repair_check" && r.verification.status === "passed" && r.photoUrl);
  const fixedEntry = [...c.history].reverse().find((h) => h.status === "fixed");
  const firstMs = Date.parse(first.createdAt);
  const ageDays = Math.max(0, (now - firstMs) / DAY_MS);

  const summary = {
    ...c,
    reports,
    severity,
    reporterCount: cred.people,
    credibility: cred.level,
    photoCount: reports.filter((r) => r.photoUrl).length,
    firstReportedAt: first.createdAt,
    lastActivityAt: [last?.createdAt, ...c.history.map((h) => h.at)]
      .filter(Boolean)
      .sort()
      .at(-1),
    fixedAt: fixedEntry?.at,
    daysToFix: fixedEntry ? Math.max(0, (Date.parse(fixedEntry.at) - firstMs) / DAY_MS) : undefined,
    ageDays,
    beforePhotoUrl: before?.photoUrl,
    afterPhotoUrl: after?.photoUrl,
    open: isOpen(c.status),
  };
  summary.priority = priorityScore(summary, now);
  summary.overdue = isOverdue(summary, now);
  return summary;
}

/**
 * Groups loose reports into cases: a report joins the earliest group of the same category whose
 * first report is within `radiusM`; otherwise it starts a new group.
 */
export function groupReports(reports, radiusM = DUPLICATE_RADIUS_M) {
  const sorted = [...reports].sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
  const groups = [];
  for (const r of sorted) {
    const home = groups.find((g) => g.category === r.category && distanceM(g, r) <= radiusM);
    if (home) home.reports.push(r);
    else groups.push({ category: r.category, lat: r.lat, lng: r.lng, reports: [r] });
  }
  return groups;
}
