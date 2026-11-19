// Numbers for the top of the portal, computed from summarized cases.

const DAY_MS = 86_400_000;
const URGENT_UNATTENDED = new Set(["new", "in_review", "reopened"]);

export function computeMetrics(cases, now) {
  const open = cases.filter((c) => c.open);
  const fixed = cases.filter((c) => c.status === "fixed" && typeof c.daysToFix === "number");
  const fixedLast30 = fixed.filter((c) => now - Date.parse(c.fixedAt) <= 30 * DAY_MS);
  const newReports24h = cases.reduce(
    (n, c) => n + c.reports.filter((r) => r.kind !== "repair_check" && now - Date.parse(r.createdAt) <= DAY_MS).length,
    0,
  );
  const avg = (xs) => (xs.length === 0 ? undefined : xs.reduce((a, b) => a + b, 0) / xs.length);
  return {
    openCases: open.length,
    newReports24h,
    urgentUnattended: open.filter((c) => c.severity === "dangerous" && URGENT_UNATTENDED.has(c.status)).length,
    overdue: open.filter((c) => c.overdue).length,
    fixedLast30: fixedLast30.length,
    avgDaysToFix: avg(fixed.map((c) => c.daysToFix)),
  };
}
