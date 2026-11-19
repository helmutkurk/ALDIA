import { test } from "node:test";
import assert from "node:assert/strict";

import { parseCase } from "../src/domain/schema.js";
import { summarizeCase } from "../src/domain/cases.js";
import {
  byZone,
  casesInPeriod,
  frequencyByCategory,
  headline,
  median,
  repairTimeByCategory,
  slaBySeverity,
  weeklyFlow,
} from "../src/domain/stats.js";
import { createMockSource } from "../src/data/mock-source.js";
import { parseCaseList } from "../src/domain/schema.js";
import { DAY, NOW, rawCase, report } from "./helpers.js";

let n = 0;
/** A case first reported `ageDays` ago; if `fixedAfter` is set, fixed that many days after. */
function makeCase({ category = "pothole", severity = "minor", ageDays = 10, fixedAfter, zone = "Zona 1", reopened = false, status }) {
  n += 1;
  const first = new Date(NOW - ageDays * DAY).toISOString();
  const history = [{ status: "new", at: first, by: "sistema" }];
  if (fixedAfter !== undefined) {
    if (reopened) history.push({ status: "fix_claimed", at: first, by: "gobierno" }, { status: "reopened", at: first, by: "sistema" });
    history.push({ status: "fix_claimed", at: first, by: "gobierno" });
    history.push({ status: "fixed", at: new Date(Date.parse(first) + fixedAfter * DAY).toISOString(), by: "sistema" });
  }
  const parsed = parseCase(
    rawCase({
      id: `ALD-T-${n}`,
      category,
      zone,
      status: status ?? (fixedAfter !== undefined ? "fixed" : "new"),
      reports: [report({ category, severity, createdAt: first })],
      history,
    }),
  );
  return summarizeCase(parsed.value, NOW);
}

test("median handles odd, even and empty lists", () => {
  assert.equal(median([5, 1, 3]), 3);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  assert.equal(median([]), undefined);
});

test("repair time per category uses fixed cases only, slowest first", () => {
  const cases = [
    makeCase({ category: "pothole", fixedAfter: 10 }),
    makeCase({ category: "pothole", fixedAfter: 20 }),
    makeCase({ category: "drain_cover", fixedAfter: 2 }),
    makeCase({ category: "street_light" }),
  ];
  const rows = repairTimeByCategory(cases);
  assert.deepEqual(rows.map((r) => r.category), ["pothole", "drain_cover"]);
  assert.equal(Math.round(rows[0].medianDays), 15);
  assert.equal(rows[0].n, 2);
});

test("frequency splits cases into fixed, open and closed, most frequent first", () => {
  const rows = frequencyByCategory([
    makeCase({ category: "street_light" }),
    makeCase({ category: "street_light", fixedAfter: 3 }),
    makeCase({ category: "street_light", status: "duplicate" }),
    makeCase({ category: "ramp" }),
  ]);
  assert.equal(rows[0].category, "street_light");
  assert.deepEqual([rows[0].fixed, rows[0].open, rows[0].closed, rows[0].total], [1, 1, 1, 3]);
  assert.equal(rows[1].category, "ramp");
});

test("headline: median repair time, share within deadline and reopen rate", () => {
  const cases = [
    makeCase({ severity: "dangerous", fixedAfter: 1 }), // within 2 days
    makeCase({ severity: "dangerous", fixedAfter: 5, reopened: true }), // late, reopened once
    makeCase({ severity: "minor", fixedAfter: 10 }), // within 30
    makeCase({}),
  ];
  const s = headline(cases);
  assert.equal(s.total, 4);
  assert.equal(s.open, 1);
  assert.equal(s.fixed, 3);
  assert.equal(Math.round(s.medianDaysToFix), 5);
  assert.equal(Math.round(s.withinSlaPct), 67);
  assert.equal(Math.round(s.reopenPct), 33);

  const sla = slaBySeverity(cases);
  const dangerous = sla.find((r) => r.severity === "dangerous");
  assert.deepEqual([dangerous.fixed, dangerous.within], [2, 1]);
  assert.equal(sla.find((r) => r.severity === "damages_cars").pct, undefined);
});

test("weekly flow counts new and fixed cases in the right week", () => {
  const rows = weeklyFlow([makeCase({ ageDays: 3, fixedAfter: 1 }), makeCase({ ageDays: 20 }), makeCase({ ageDays: 200 })], NOW, 8);
  assert.equal(rows.length, 8);
  assert.equal(rows.reduce((s, r) => s + r.reported, 0), 2);
  assert.equal(rows.at(-1).reported, 1);
  assert.equal(rows.at(-1).fixed, 1);
});

test("period filter and zones", () => {
  const cases = [makeCase({ ageDays: 5, zone: "Zona 4", severity: "dangerous" }), makeCase({ ageDays: 60, zone: "Zona 1" })];
  assert.equal(casesInPeriod(cases, 30, NOW).length, 1);
  assert.equal(casesInPeriod(cases, 0, NOW).length, 2);
  const zones = byZone(cases);
  assert.equal(zones[0].zone, "Zona 4");
  assert.equal(zones[0].dangerousOpen, 1);
});

test("synthetic data gives every statistic something to show", async () => {
  const parsed = parseCaseList(await createMockSource({ now: NOW }).listCases());
  const cases = parsed.value.cases.map((c) => summarizeCase(c, NOW));
  assert.ok(repairTimeByCategory(cases).length >= 4);
  assert.ok(headline(cases).reopenPct > 0);
  assert.ok(weeklyFlow(cases, NOW).some((w) => w.fixed > 0));
});
