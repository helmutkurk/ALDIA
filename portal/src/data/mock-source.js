// In-memory data source with synthetic Guatemala City cases, for building and demonstrating the
// portal before the backend exists. It has the same interface as the API source and returns the
// same JSON shape as `GET /cases` (see docs/api-contract.md), so the rest of the portal cannot
// tell them apart. All places, people and photos are synthetic.

import { canTransition, statusAfterRepairCheck, statusLabel } from "../domain/statuses.js";
import { syntheticPhoto } from "./synthetic-photos.js";

const DAY_MS = 86_400_000;

/** Small deterministic PRNG so the demo looks the same on every load. */
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Approximate zone centres, only to spread synthetic points over the city.
const ZONES = [
  { zone: "Zona 1", lat: 14.6405, lng: -90.5135 },
  { zone: "Zona 2", lat: 14.6525, lng: -90.5125 },
  { zone: "Zona 4", lat: 14.6228, lng: -90.5158 },
  { zone: "Zona 5", lat: 14.6245, lng: -90.4985 },
  { zone: "Zona 9", lat: 14.6052, lng: -90.5172 },
  { zone: "Zona 10", lat: 14.6025, lng: -90.5072 },
  { zone: "Zona 11", lat: 14.6105, lng: -90.5445 },
  { zone: "Zona 12", lat: 14.5905, lng: -90.5305 },
];

const CATEGORY_WEIGHTS = [
  ["pothole", 9],
  ["sidewalk", 4],
  ["street_light", 4],
  ["drain_cover", 3],
  ["ramp", 3],
  ["signage", 2],
];

const PATHS = {
  new: ["new"],
  in_review: ["new", "in_review"],
  scheduled: ["new", "in_review", "scheduled"],
  in_progress: ["new", "scheduled", "in_progress"],
  fix_claimed: ["new", "in_review", "in_progress", "fix_claimed"],
  reopened: ["new", "in_progress", "fix_claimed", "reopened"],
  fixed: ["new", "in_review", "in_progress", "fix_claimed", "fixed"],
  not_responsible: ["new", "not_responsible"],
  duplicate: ["new", "duplicate"],
};

const STATUS_PLAN = [
  ["new", 12],
  ["in_review", 8],
  ["scheduled", 6],
  ["in_progress", 7],
  ["fix_claimed", 4],
  ["reopened", 2],
  ["fixed", 9],
  ["not_responsible", 1],
  ["duplicate", 1],
];

const NOTES = {
  new: undefined,
  in_review: "Asignado a la Dirección de Obras para revisión.",
  scheduled: "Programado en el plan de bacheo de la próxima semana.",
  in_progress: "Cuadrilla en sitio.",
  fix_claimed: "La cuadrilla reporta el trabajo terminado.",
  fixed: "Un vecino tomó la foto de después y el verificador confirmó la reparación.",
  reopened: "La foto de después todavía muestra el problema.",
  not_responsible: "Corresponde a COVIAL (carretera nacional).",
  duplicate: "Duplicado de otro caso en la misma esquina.",
};

const SYSTEM_STATUSES = new Set(["new", "fixed", "reopened"]);

export function createMockSource({ now = Date.now(), seed = 1902 } = {}) {
  const rand = mulberry32(seed);
  const pick = (xs) => xs[Math.floor(rand() * xs.length)];
  const between = (lo, hi) => lo + rand() * (hi - lo);
  const weighted = (pairs) => {
    const total = pairs.reduce((s, [, w]) => s + w, 0);
    let r = rand() * total;
    for (const [v, w] of pairs) if ((r -= w) <= 0) return v;
    return pairs[0][0];
  };

  let reportSeq = 1000;
  let caseSeq = 4800;
  const nextReporter = () => `vec_${Math.floor(rand() * 400).toString(36)}${Math.floor(rand() * 1e6).toString(36)}`;

  function severityFor(category) {
    if (category === "drain_cover") return weighted([["dangerous", 4], ["damages_cars", 1]]);
    if (category === "pothole") return weighted([["damages_cars", 5], ["dangerous", 1], ["minor", 2]]);
    if (category === "signage") return weighted([["minor", 2], ["dangerous", 1]]);
    return weighted([["minor", 3], ["damages_cars", 1]]);
  }

  function makeReport(c, { at, kind = "report", reporterId = nextReporter(), verification, after = false }) {
    reportSeq += 1;
    return {
      id: `rep_${reportSeq}`,
      kind,
      category: c.category,
      lat: c.lat + between(-0.00008, 0.00008),
      lng: c.lng + between(-0.00008, 0.00008),
      accuracyM: Math.round(between(4, 15)),
      createdAt: new Date(at).toISOString(),
      severity: c.severity,
      reporterId,
      verification: verification ?? { status: "passed", confidence: Number(between(0.78, 0.98).toFixed(2)) },
      photoUrl: syntheticPhoto(c.category, { after }),
    };
  }

  function makeCase(status, at = now) {
    caseSeq += 1;
    const z = pick(ZONES);
    const category = weighted(CATEGORY_WEIGHTS);
    const ageDays = {
      new: between(0.05, 6),
      in_review: between(1, 10),
      scheduled: between(3, 20),
      in_progress: between(4, 25),
      fix_claimed: between(6, 30),
      reopened: between(10, 40),
      fixed: between(8, 60),
      not_responsible: between(5, 30),
      duplicate: between(2, 20),
    }[status];
    const avenue = 1 + Math.floor(rand() * 14);
    const street = 1 + Math.floor(rand() * 20);
    const c = {
      id: `ALD-GT-${String(caseSeq).padStart(5, "0")}`,
      category,
      status,
      lat: Number((z.lat + between(-0.006, 0.006)).toFixed(6)),
      lng: Number((z.lng + between(-0.006, 0.006)).toFixed(6)),
      address: `${avenue}a. Avenida y ${street} Calle, ${z.zone}`,
      zone: z.zone,
      nearSensitive: rand() < 0.2,
      severity: severityFor(category),
      reports: [],
      history: [],
    };
    const start = at - ageDays * DAY_MS;
    const end = status === "fixed" ? start + between(0.3, 0.85) * (at - start) : at;

    // Problem reports: 1-6, mostly from different people; sometimes the same person twice.
    const count = weighted([[1, 5], [2, 4], [3, 3], [4, 2], [6, 1]]);
    const people = [];
    for (let i = 0; i < count; i += 1) {
      const reporterId = i > 0 && rand() < 0.15 ? people[0] : nextReporter();
      people.push(reporterId);
      const t = i === 0 ? start : start + rand() * (end - start) * 0.7;
      const latest = i === count - 1 && status === "new" && rand() < 0.4;
      const failed = !latest && rand() < 0.05;
      c.reports.push(
        makeReport(c, {
          at: t,
          reporterId,
          verification: latest
            ? { status: "pending" }
            : failed
              ? { status: "failed", reason: "La foto está borrosa." }
              : undefined,
        }),
      );
    }

    // History along the path, spread between the first report and `end`.
    const path = PATHS[status];
    path.forEach((s, i) => {
      const t = i === 0 ? start : start + ((end - start) * i) / path.length;
      c.history.push({ status: s, at: new Date(t).toISOString(), by: SYSTEM_STATUSES.has(s) ? "sistema" : "gobierno", note: NOTES[s] });
    });
    if (status === "fixed") {
      c.reports.push(makeReport(c, { at: end, kind: "repair_check", after: true }));
    }
    if (status === "reopened") {
      const t = Date.parse(c.history.at(-1).at);
      c.reports.push(
        makeReport(c, {
          at: t,
          kind: "repair_check",
          verification: { status: "failed", reason: "La foto de después todavía muestra el problema." },
        }),
      );
    }
    if (category === "pothole" && c.severity === "dangerous") c.nearSensitive = true;
    return c;
  }

  const cases = [];
  for (const [status, n] of STATUS_PLAN) for (let i = 0; i < n; i += 1) cases.push(makeCase(status));
  const byId = new Map(cases.map((c) => [c.id, c]));

  /** Simulates citizens: sometimes a new report arrives, on an open case or a new spot. */
  function tick(t) {
    if (rand() > 0.55) return;
    const open = cases.filter((c) => ["new", "in_review", "scheduled", "in_progress"].includes(c.status));
    if (open.length > 0 && rand() < 0.65) {
      const c = pick(open);
      c.reports.push(makeReport(c, { at: t }));
    } else {
      const c = makeCase("new", t);
      c.reports = [c.reports[0]];
      c.reports[0].createdAt = new Date(t).toISOString();
      c.history = [{ status: "new", at: new Date(t).toISOString(), by: "sistema" }];
      cases.push(c);
      byId.set(c.id, c);
    }
  }

  const toWire = (c) => {
    const { severity: _severity, ...wire } = c;
    return structuredClone(wire);
  };

  let lastTick = now;

  return {
    kind: "mock",
    supportsSimulation: true,

    async listCases() {
      const t = Date.now();
      if (t - lastTick > 5_000) {
        tick(t);
        lastTick = t;
      }
      return { cases: cases.map(toWire), serverTime: new Date(t).toISOString() };
    },

    async setStatus(id, status, note) {
      const c = byId.get(id);
      if (!c) throw new Error("No se encontró el caso.");
      if (!canTransition(c.status, status)) {
        throw new Error(`No se puede pasar de "${statusLabel(c.status)}" a "${statusLabel(status)}".`);
      }
      c.status = status;
      c.history.push({ status, at: new Date().toISOString(), by: "gobierno", note: note || undefined });
      return toWire(c);
    },

    /** Demo only: a citizen sends the "after" photo; the verifier passes or fails it. */
    async simulateRepairCheck(id, passed) {
      const c = byId.get(id);
      if (!c) throw new Error("No se encontró el caso.");
      const t = Date.now();
      c.reports.push(
        makeReport(c, {
          at: t,
          kind: "repair_check",
          after: passed,
          verification: passed
            ? undefined
            : { status: "failed", reason: "La foto de después todavía muestra el problema." },
        }),
      );
      const next = statusAfterRepairCheck(c.status, passed);
      if (next !== c.status) {
        c.status = next;
        c.history.push({ status: next, at: new Date(t).toISOString(), by: "sistema", note: NOTES[next] });
      }
      return toWire(c);
    },
  };
}
