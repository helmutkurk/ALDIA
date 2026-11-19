import { statusGroup } from "./statuses.js";

const DAY_MS = 86_400_000;

export const DEFAULT_FILTERS = Object.freeze({
  categories: [], // empty = all
  view: "open", // "open" | "fixed" | "closed" | "all"
  periodDays: 0, // 0 = all time, else cases with activity in the last N days
  urgentOnly: false,
  text: "",
});

const normalize = (s) =>
  s
    .toLocaleLowerCase("es")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");

export function applyFilters(cases, filters, now) {
  const f = { ...DEFAULT_FILTERS, ...filters };
  const text = normalize(f.text.trim());
  return cases.filter((c) => {
    if (f.categories.length > 0 && !f.categories.includes(c.category)) return false;
    if (f.view !== "all" && statusGroup(c.status) !== f.view) return false;
    if (f.periodDays > 0 && now - Date.parse(c.lastActivityAt) > f.periodDays * DAY_MS) return false;
    if (f.urgentOnly && !(c.severity === "dangerous" || c.overdue)) return false;
    if (text) {
      const haystack = normalize(`${c.id} ${c.address ?? ""} ${c.zone ?? ""}`);
      if (!haystack.includes(text)) return false;
    }
    return true;
  });
}

/** Highest priority first; ties: oldest first report first. */
export function sortForQueue(cases) {
  return [...cases].sort(
    (a, b) => b.priority - a.priority || Date.parse(a.firstReportedAt) - Date.parse(b.firstReportedAt),
  );
}
