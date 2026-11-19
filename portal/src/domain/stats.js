// Statistics for the "Estadísticas" page, computed from summarized cases (see cases.js).
// Pure functions so every number on the page is testable.

import { CATEGORIES } from "./categories.js";
import { SEVERITIES } from "./schema.js";
import { statusGroup } from "./statuses.js";
import { slaDays } from "./priority.js";

const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;

export function median(xs) {
  if (xs.length === 0) return undefined;
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

const mean = (xs) => (xs.length === 0 ? undefined : xs.reduce((a, b) => a + b, 0) / xs.length);
const fixedCases = (cases) => cases.filter((c) => c.status === "fixed" && typeof c.daysToFix === "number");
const withinSla = (c) => c.daysToFix <= slaDays(c.severity);

/** Keeps cases first reported within the last `days` (0 = all). */
export function casesInPeriod(cases, days, now) {
  if (!days) return cases;
  return cases.filter((c) => now - Date.parse(c.firstReportedAt) <= days * DAY_MS);
}

export function headline(cases) {
  const fixed = fixedCases(cases);
  const everClaimed = cases.filter((c) => c.history.some((h) => h.status === "fix_claimed"));
  const reopened = everClaimed.filter((c) => c.history.some((h) => h.status === "reopened"));
  return {
    total: cases.length,
    open: cases.filter((c) => statusGroup(c.status) === "open").length,
    fixed: fixed.length,
    medianDaysToFix: median(fixed.map((c) => c.daysToFix)),
    withinSlaPct: fixed.length === 0 ? undefined : (fixed.filter(withinSla).length / fixed.length) * 100,
    reopenPct: everClaimed.length === 0 ? undefined : (reopened.length / everClaimed.length) * 100,
  };
}

/** Repair time per category, slowest (by median) first. Categories without fixed cases are left out. */
export function repairTimeByCategory(cases) {
  return CATEGORIES.map(({ id, label }) => {
    const days = fixedCases(cases)
      .filter((c) => c.category === id)
      .map((c) => c.daysToFix);
    return { category: id, label, n: days.length, medianDays: median(days), avgDays: mean(days) };
  })
    .filter((r) => r.n > 0)
    .sort((a, b) => b.medianDays - a.medianDays);
}

/** Most frequent problems: cases per category split into fixed / open / closed, most cases first. */
export function frequencyByCategory(cases) {
  return CATEGORIES.map(({ id, label }) => {
    const own = cases.filter((c) => c.category === id);
    const count = (group) => own.filter((c) => statusGroup(c.status) === group).length;
    return {
      category: id,
      label,
      fixed: count("fixed"),
      open: count("open"),
      closed: count("closed"),
      total: own.length,
      reports: own.reduce((n, c) => n + c.reports.filter((r) => r.kind !== "repair_check").length, 0),
    };
  })
    .filter((r) => r.total > 0)
    .sort((a, b) => b.total - a.total);
}

/** New cases and fixed cases per week for the last `weeks` weeks, oldest first. */
export function weeklyFlow(cases, now, weeks = 8) {
  const start = now - weeks * WEEK_MS;
  const rows = Array.from({ length: weeks }, (_, i) => ({ weekStart: new Date(start + i * WEEK_MS).toISOString(), reported: 0, fixed: 0 }));
  const slot = (iso) => {
    const t = Date.parse(iso);
    if (t < start || t > now) return undefined;
    return rows[Math.min(weeks - 1, Math.floor((t - start) / WEEK_MS))];
  };
  for (const c of cases) {
    const r = slot(c.firstReportedAt);
    if (r) r.reported += 1;
    if (c.status === "fixed" && c.fixedAt) {
      const f = slot(c.fixedAt);
      if (f) f.fixed += 1;
    }
  }
  return rows;
}

/** Share of fixed cases repaired within the deadline, per severity. */
export function slaBySeverity(cases) {
  return SEVERITIES.map((severity) => {
    const fixed = fixedCases(cases).filter((c) => c.severity === severity);
    const openOverdue = cases.filter((c) => c.severity === severity && c.open && c.overdue).length;
    return {
      severity,
      slaDays: slaDays(severity),
      fixed: fixed.length,
      within: fixed.filter(withinSla).length,
      pct: fixed.length === 0 ? undefined : (fixed.filter(withinSla).length / fixed.length) * 100,
      openOverdue,
    };
  });
}

/** One row per zone, most open cases first. */
export function byZone(cases) {
  const zones = new Map();
  for (const c of cases) {
    const key = c.zone ?? "Sin zona";
    if (!zones.has(key)) zones.set(key, []);
    zones.get(key).push(c);
  }
  return [...zones.entries()]
    .map(([zone, own]) => {
      const fixed = fixedCases(own);
      return {
        zone,
        open: own.filter((c) => c.open).length,
        dangerousOpen: own.filter((c) => c.open && c.severity === "dangerous").length,
        overdue: own.filter((c) => c.open && c.overdue).length,
        fixed: fixed.length,
        medianDaysToFix: median(fixed.map((c) => c.daysToFix)),
      };
    })
    .sort((a, b) => b.open - a.open || b.dangerousOpen - a.dangerousOpen || a.zone.localeCompare(b.zone, "es"));
}
