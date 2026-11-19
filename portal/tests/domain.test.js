import { test } from "node:test";
import assert from "node:assert/strict";

import { allowedTransitions, canTransition, statusAfterRepairCheck, isOpen } from "../src/domain/statuses.js";
import { parseCase, parseCaseList, parseReport, safeMediaUrl } from "../src/domain/schema.js";
import { credibility, groupReports, summarizeCase } from "../src/domain/cases.js";
import { priorityScore, isOverdue } from "../src/domain/priority.js";
import { computeMetrics } from "../src/domain/metrics.js";
import { applyFilters, sortForQueue } from "../src/domain/filters.js";
import { clusterPoints } from "../src/domain/cluster.js";
import { toGeoJSON, toOpen311 } from "../src/domain/exports.js";
import { distanceM } from "../src/domain/geo.js";
import { DAY, NOW, rawCase, report } from "./helpers.js";

const summarize = (overrides) => summarizeCase(parseCase(rawCase(overrides)).value, NOW);

test("a government user can never set 'fixed' by hand", () => {
  for (const from of Object.keys({ new: 1, in_review: 1, scheduled: 1, in_progress: 1, reopened: 1 })) {
    assert.equal(canTransition(from, "fixed"), false, from);
  }
  assert.deepEqual(allowedTransitions("fix_claimed"), []);
  assert.equal(canTransition("in_progress", "fix_claimed"), true);
});

test("a passed after-photo fixes the case; a failed one reopens a claimed fix", () => {
  assert.equal(statusAfterRepairCheck("fix_claimed", true), "fixed");
  assert.equal(statusAfterRepairCheck("in_progress", true), "fixed");
  assert.equal(statusAfterRepairCheck("fix_claimed", false), "reopened");
  assert.equal(statusAfterRepairCheck("in_progress", false), "in_progress");
  assert.equal(statusAfterRepairCheck("fixed", true), "fixed");
  assert.equal(isOpen("fix_claimed"), true);
  assert.equal(isOpen("fixed"), false);
});

test("schema rejects bad input and unsafe photo URLs", () => {
  assert.equal(parseReport(report({ lat: 120 })).ok, false);
  assert.equal(parseReport(report({ category: "people" })).ok, false);
  assert.equal(parseReport(report({ id: "<script>" })).ok, false);
  assert.equal(parseReport(report({ photoUrl: "javascript:alert(1)" })).ok, false);
  assert.equal(safeMediaUrl("http://evil.example/x.jpg"), null);
  assert.equal(safeMediaUrl("//evil.example/x.jpg"), null);
  assert.equal(safeMediaUrl("/api/v1/photos/pho_1"), "/api/v1/photos/pho_1");
  assert.equal(safeMediaUrl("http://127.0.0.1:8080/p.jpg"), "http://127.0.0.1:8080/p.jpg");
  assert.ok(safeMediaUrl("data:image/svg+xml;charset=utf-8,%3Csvg%3E"));
  assert.equal(safeMediaUrl("data:text/html,hi"), null);
  assert.equal(parseReport(report()).ok, true);
});

test("schema drops invalid reports, keeps the case, and rejects a case without valid reports", () => {
  const parsed = parseCase(rawCase({ reports: [report(), report({ lat: "x" }), report({ category: "ramp" })] }));
  assert.equal(parsed.ok, true);
  assert.equal(parsed.value.reports.length, 1);
  assert.equal(parsed.value.dropped, 2);
  assert.equal(parseCase(rawCase({ reports: [report({ lat: 999 })] })).ok, false);

  const list = parseCaseList({ cases: [rawCase(), { id: "bad" }], serverTime: new Date(NOW).toISOString() });
  assert.equal(list.value.cases.length, 1);
  assert.equal(list.value.rejected, 1);
  assert.equal(parseCaseList({}).ok, false);
});

test("credibility counts independent people with a verified photo, not photos", () => {
  const same = report({ reporterId: "vec_a" });
  assert.deepEqual(credibility([same, report({ reporterId: "vec_a" })]), { level: "single", people: 1 });
  assert.equal(credibility([report({ reporterId: "vec_a" }), report({ reporterId: "vec_b" })]).level, "corroborated");
  assert.equal(credibility([report({ verification: { status: "pending" } })]).level, "pending");
  assert.equal(credibility([report({ verification: { status: "failed" } }), report({ kind: "repair_check" })]).level, "pending");
});

test("summary finds before and after photos and days to fix", () => {
  const first = report({ createdAt: new Date(NOW - 10 * DAY).toISOString(), photoUrl: "https://x.org/before.jpg" });
  const after = report({ kind: "repair_check", createdAt: new Date(NOW - 3 * DAY).toISOString(), photoUrl: "https://x.org/after.jpg" });
  const c = summarize({
    status: "fixed",
    reports: [after, first],
    history: [
      { status: "new", at: first.createdAt, by: "sistema" },
      { status: "fixed", at: after.createdAt, by: "sistema" },
    ],
  });
  assert.equal(c.beforePhotoUrl, "https://x.org/before.jpg");
  assert.equal(c.afterPhotoUrl, "https://x.org/after.jpg");
  assert.equal(Math.round(c.daysToFix), 7);
  assert.equal(c.priority, 0);
  assert.equal(c.open, false);
});

test("loose reports group by category within 20 m", () => {
  const a = report({ lat: 14.64, lng: -90.51 });
  const near = report({ lat: 14.64005, lng: -90.51005 }); // about 7 m away
  const otherCategory = report({ category: "street_light", lat: 14.64, lng: -90.51 });
  const far = report({ lat: 14.6406, lng: -90.51 }); // about 67 m away
  assert.ok(distanceM(a, near) < 20);
  const groups = groupReports([a, near, otherCategory, far]);
  assert.equal(groups.length, 3);
  assert.equal(groups.find((g) => g.reports.includes(a)).reports.length, 2);
});

test("priority: dangerous beats minor, more people and age raise it, closed is zero", () => {
  const base = { status: "new", firstReportedAt: new Date(NOW - DAY).toISOString(), reporterCount: 1 };
  const minor = priorityScore({ ...base, severity: "minor" }, NOW);
  const dangerous = priorityScore({ ...base, severity: "dangerous" }, NOW);
  assert.ok(dangerous > minor);
  assert.ok(priorityScore({ ...base, severity: "minor", reporterCount: 4 }, NOW) > minor);
  assert.ok(priorityScore({ ...base, severity: "minor", firstReportedAt: new Date(NOW - 20 * DAY).toISOString() }, NOW) > minor);
  assert.ok(priorityScore({ ...base, severity: "dangerous", reporterCount: 9, nearSensitive: true, firstReportedAt: new Date(NOW - 90 * DAY).toISOString() }, NOW) <= 100);
  assert.equal(priorityScore({ ...base, severity: "dangerous", status: "fixed" }, NOW), 0);
  assert.equal(isOverdue({ ...base, severity: "dangerous", firstReportedAt: new Date(NOW - 3 * DAY).toISOString() }, NOW), true);
  assert.equal(isOverdue({ ...base, severity: "minor", firstReportedAt: new Date(NOW - 3 * DAY).toISOString() }, NOW), false);
});

test("metrics count open, new, urgent, overdue and average repair time", () => {
  const dangerous = summarize({ id: "ALD-1", reports: [report({ severity: "dangerous", createdAt: new Date(NOW - 5 * DAY).toISOString() })] });
  const fresh = summarize({ id: "ALD-2", reports: [report({ createdAt: new Date(NOW - 3_600_000).toISOString() })] });
  const r = report({ createdAt: new Date(NOW - 6 * DAY).toISOString() });
  const fixed = summarize({
    id: "ALD-3",
    status: "fixed",
    reports: [r],
    history: [{ status: "fixed", at: new Date(NOW - 2 * DAY).toISOString(), by: "sistema" }],
  });
  const m = computeMetrics([dangerous, fresh, fixed], NOW);
  assert.equal(m.openCases, 2);
  assert.equal(m.newReports24h, 1);
  assert.equal(m.urgentUnattended, 1);
  assert.equal(m.overdue, 1);
  assert.equal(m.fixedLast30, 1);
  assert.equal(Math.round(m.avgDaysToFix), 4);
});

test("filters by view, category, urgency and text; queue sorts by priority", () => {
  const a = summarize({ id: "ALD-A", address: "6a. Avenida, Zona 1", reports: [report({ severity: "dangerous" })] });
  const b = summarize({ id: "ALD-B", category: "street_light", address: "Calle Martí, Zona 2", reports: [report({ category: "street_light", severity: "minor" })] });
  const c = summarize({ id: "ALD-C", status: "fixed", reports: [report()] });
  const all = [b, a, c];
  assert.deepEqual(applyFilters(all, { view: "open" }, NOW).map((x) => x.id).sort(), ["ALD-A", "ALD-B"]);
  assert.deepEqual(applyFilters(all, { view: "fixed" }, NOW).map((x) => x.id), ["ALD-C"]);
  assert.deepEqual(applyFilters(all, { view: "all", categories: ["street_light"] }, NOW).map((x) => x.id), ["ALD-B"]);
  assert.deepEqual(applyFilters(all, { urgentOnly: true }, NOW).map((x) => x.id), ["ALD-A"]);
  assert.deepEqual(applyFilters(all, { text: "marti" }, NOW).map((x) => x.id), ["ALD-B"]);
  assert.deepEqual(sortForQueue([b, a]).map((x) => x.id), ["ALD-A", "ALD-B"]);
});

test("grid clustering groups nearby screen points", () => {
  const groups = clusterPoints(
    [
      { x: 10, y: 10 },
      { x: 20, y: 30 },
      { x: 200, y: 200 },
    ],
    56,
  );
  assert.equal(groups.length, 2);
  const big = groups.find((g) => g.members.length === 2);
  assert.deepEqual([big.x, big.y], [15, 20]);
});

test("exports: Open311 status mapping and no reporter ids; GeoJSON uses lng,lat order", () => {
  const open = summarize({ reports: [report({ reporterId: "vec_secret" })] });
  const o = toOpen311(open, { agency: "Municipalidad" });
  assert.equal(o.status, "open");
  assert.equal(o.service_code, "pothole");
  assert.equal(o.long, open.lng);
  assert.ok(!JSON.stringify(o).includes("vec_secret"));
  assert.equal(toOpen311(summarize({ status: "duplicate" })).status, "closed");

  const geo = toGeoJSON([open]);
  assert.deepEqual(geo.features[0].geometry.coordinates, [open.lng, open.lat]);
  assert.ok(!JSON.stringify(geo).includes("vec_secret"));
});
