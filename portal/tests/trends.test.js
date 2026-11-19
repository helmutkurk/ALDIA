import { test } from "node:test";
import assert from "node:assert/strict";

import { parseCase } from "../src/domain/schema.js";
import { summarizeCase } from "../src/domain/cases.js";
import { delta, kpiTrends, sparklinePoints, statusAt } from "../src/domain/trends.js";
import { DAY, NOW, rawCase, report } from "./helpers.js";

const iso = (daysAgo) => new Date(NOW - daysAgo * DAY).toISOString();

function make(id, { ageDays, severity = "minor", history = [], reports }) {
  const parsed = parseCase(
    rawCase({
      id,
      status: history.at(-1)?.status ?? "new",
      reports: reports ?? [report({ severity, createdAt: iso(ageDays) })],
      history: [{ status: "new", at: iso(ageDays), by: "sistema" }, ...history],
    }),
  );
  return summarizeCase(parsed.value, NOW);
}

test("statusAt rebuilds the status at a past moment from the history", () => {
  const c = make("A", {
    ageDays: 40,
    history: [
      { status: "in_progress", at: iso(20), by: "gobierno" },
      { status: "fixed", at: iso(5), by: "sistema" },
    ],
  });
  assert.equal(statusAt(c, NOW - 50 * DAY), null);
  assert.equal(statusAt(c, NOW - 30 * DAY), "new");
  assert.equal(statusAt(c, NOW - 10 * DAY), "in_progress");
  assert.equal(statusAt(c, NOW), "fixed");
});

test("KPI trends compare against the previous period", () => {
  const fixedRecently = make("A", { ageDays: 40, history: [{ status: "fixed", at: iso(5), by: "sistema" }] });
  const stillOpen = make("B", { ageDays: 45, severity: "dangerous" });
  const newToday = make("C", { ageDays: 0.2 });
  const t = kpiTrends([fixedRecently, stillOpen, newToday], NOW);
  assert.equal(t.open.value, 2); // B and C
  assert.equal(t.open.previous, 2); // A and B were open 30 days ago
  assert.equal(t.newReports.value, 1);
  assert.equal(t.dangerous.value, 1);
  assert.equal(Math.round(t.repairDays.value), 35);
  assert.equal(t.repairDays.previous, undefined);
  assert.equal(t.open.series.length, 8);
});

test("delta text and tone: lower is better", () => {
  assert.deepEqual(delta(10, 7), { text: "▲ 3", tone: "bad" });
  assert.deepEqual(delta(5, 8), { text: "▼ 3", tone: "good" });
  assert.deepEqual(delta(16.8, 18, { unit: " d", digits: 1 }), { text: "▼ 1.2 d", tone: "good" });
  assert.deepEqual(delta(4, 4), { text: "Sin cambio", tone: "neutral" });
  assert.equal(delta(undefined, 3).text, undefined);
  assert.deepEqual(delta(60, 50, { unit: " pts", lowerIsBetter: false }), { text: "▲ 10 pts", tone: "good" });
});

test("sparkline points skip missing values and need two points", () => {
  assert.equal(sparklinePoints([1, undefined]), "");
  const pts = sparklinePoints([0, undefined, 10], 88, 28, 2).split(" ");
  assert.equal(pts.length, 2);
  assert.deepEqual(pts, ["2.0,26.0", "86.0,2.0"]);
});
