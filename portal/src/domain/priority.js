// Priority score 0-100 for the work queue. A proposal to tune with the first government user:
// severity weighs most, then independent people who reported it, then age, then whether it is
// next to a school or hospital. Closed and fixed cases score 0.

import { isOpen } from "./statuses.js";

const DAY_MS = 86_400_000;
const SEVERITY_POINTS = { minor: 15, damages_cars: 30, dangerous: 50 };

/** Days a case may stay open before it counts as overdue. Proposal, to agree with the government. */
export const SLA_DAYS = Object.freeze({ minor: 30, damages_cars: 15, dangerous: 2 });

export function priorityScore(c, now) {
  if (!isOpen(c.status)) return 0;
  const ageDays = Math.max(0, (now - Date.parse(c.firstReportedAt)) / DAY_MS);
  let score = SEVERITY_POINTS[c.severity] ?? SEVERITY_POINTS.minor;
  score += Math.min(c.reporterCount ?? 0, 5) * 5;
  score += (Math.min(ageDays, 30) / 30) * 15;
  if (c.nearSensitive) score += 10;
  return Math.min(100, Math.round(score));
}

export function isOverdue(c, now) {
  if (!isOpen(c.status)) return false;
  const ageDays = (now - Date.parse(c.firstReportedAt)) / DAY_MS;
  return ageDays > (SLA_DAYS[c.severity] ?? SLA_DAYS.minor);
}

export function slaDays(severity) {
  return SLA_DAYS[severity] ?? SLA_DAYS.minor;
}
