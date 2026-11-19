// Values over time for the KPI cards: the change against the previous period and a small weekly
// trend line. A case's status at any past moment is rebuilt from its history.

import { isOpen } from "./statuses.js";

const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;
const UNATTENDED = new Set(["new", "in_review", "reopened"]);

/** Status of a case at time `t`, or null if it did not exist yet. */
export function statusAt(c, t) {
  if (Date.parse(c.firstReportedAt) > t) return null;
  let status = "new";
  for (const h of [...c.history].sort((a, b) => Date.parse(a.at) - Date.parse(b.at))) {
    if (Date.parse(h.at) <= t) status = h.status;
  }
  return status;
}

const openAt = (cases, t) => cases.filter((c) => {
  const s = statusAt(c, t);
  return s !== null && isOpen(s);
}).length;

const dangerousUnattendedAt = (cases, t) =>
  cases.filter((c) => c.severity === "dangerous" && UNATTENDED.has(statusAt(c, t))).length;

const reportsBetween = (cases, from, to) =>
  cases.reduce(
    (n, c) => n + c.reports.filter((r) => r.kind !== "repair_check" && Date.parse(r.createdAt) > from && Date.parse(r.createdAt) <= to).length,
    0,
  );

function avgRepairBetween(cases, from, to) {
  const days = cases
    .filter((c) => c.status === "fixed" && c.fixedAt && Date.parse(c.fixedAt) > from && Date.parse(c.fixedAt) <= to)
    .map((c) => c.daysToFix);
  return days.length === 0 ? undefined : days.reduce((a, b) => a + b, 0) / days.length;
}

/** Points at the end of each of the last `weeks` weeks, oldest first. */
const weekEnds = (now, weeks) => Array.from({ length: weeks }, (_, i) => now - (weeks - 1 - i) * WEEK_MS);

/**
 * The four map-page KPIs, each with its current value, the value one period earlier and an 8-week
 * series. Lower is better for all four, so a rise is shown as bad.
 */
export function kpiTrends(cases, now, weeks = 8) {
  const ends = weekEnds(now, weeks);
  return {
    open: {
      value: openAt(cases, now),
      previous: openAt(cases, now - 30 * DAY_MS),
      series: ends.map((t) => openAt(cases, t)),
      versus: "vs. hace 30 días",
    },
    newReports: {
      value: reportsBetween(cases, now - DAY_MS, now),
      previous: reportsBetween(cases, now - 2 * DAY_MS, now - DAY_MS),
      series: ends.map((t) => reportsBetween(cases, t - WEEK_MS, t)),
      versus: "vs. las 24 h anteriores",
    },
    dangerous: {
      value: dangerousUnattendedAt(cases, now),
      previous: dangerousUnattendedAt(cases, now - 30 * DAY_MS),
      series: ends.map((t) => dangerousUnattendedAt(cases, t)),
      versus: "vs. hace 30 días",
    },
    repairDays: {
      value: avgRepairBetween(cases, now - 30 * DAY_MS, now),
      previous: avgRepairBetween(cases, now - 60 * DAY_MS, now - 30 * DAY_MS),
      series: ends.map((t) => avgRepairBetween(cases, t - 4 * WEEK_MS, t)),
      versus: "vs. los 30 días anteriores",
    },
  };
}

/**
 * Change between two values for display. `lowerIsBetter` decides the tone.
 * Returns { text, tone } with tone "good" | "bad" | "neutral"; text undefined when not comparable.
 */
export function delta(value, previous, { unit = "", digits = 0, lowerIsBetter = true } = {}) {
  if (value === undefined || previous === undefined) return { text: undefined, tone: "neutral" };
  const diff = value - previous;
  const rounded = Number(Math.abs(diff).toFixed(digits));
  if (rounded === 0) return { text: "Sin cambio", tone: "neutral" };
  const up = diff > 0;
  const number = rounded.toLocaleString("es-GT", { minimumFractionDigits: digits, maximumFractionDigits: digits });
  return { text: `${up ? "▲" : "▼"} ${number}${unit}`, tone: up === lowerIsBetter ? "bad" : "good" };
}

/** Polyline points for a small sparkline; missing values are skipped. */
export function sparklinePoints(series, width = 88, height = 28, pad = 2) {
  const known = series.map((v, i) => ({ v, i })).filter((p) => typeof p.v === "number");
  if (known.length < 2) return "";
  const values = known.map((p) => p.v);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  const stepX = (width - 2 * pad) / Math.max(1, series.length - 1);
  return known
    .map((p) => `${(pad + p.i * stepX).toFixed(1)},${(height - pad - ((p.v - min) / span) * (height - 2 * pad)).toFixed(1)}`)
    .join(" ");
}
