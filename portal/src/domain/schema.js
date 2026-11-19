// Validation of data that comes from the backend (or the mock source). Everything that reaches the
// portal is untrusted: ids, text, URLs and coordinates are checked before rendering. Invalid
// reports are dropped and counted, never shown half-parsed.

import { CATEGORY_IDS } from "./categories.js";
import { STATUS_IDS } from "./statuses.js";
import { isLatLng } from "./geo.js";

export const SEVERITIES = Object.freeze(["minor", "damages_cars", "dangerous"]);
export const SEVERITY_LABELS = Object.freeze({
  minor: "Molesta",
  damages_cars: "Daña vehículos",
  dangerous: "Peligroso",
});
export const REPORT_KINDS = Object.freeze(["report", "confirm", "repair_check"]);
export const VERIFICATION_STATES = Object.freeze(["passed", "failed", "pending"]);
export const HISTORY_ACTORS = Object.freeze(["gobierno", "sistema", "vecino"]);

const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const MAX_TEXT = 500;
const MAX_MEDIA_URL = 1_500_000;

const isObject = (v) => typeof v === "object" && v !== null && !Array.isArray(v);
const isIso = (v) => typeof v === "string" && v.length <= 40 && !Number.isNaN(Date.parse(v));
const isId = (v) => typeof v === "string" && ID_RE.test(v);

function optionalText(v, max = MAX_TEXT) {
  if (v === undefined || v === null || v === "") return undefined;
  if (typeof v !== "string") return null;
  return v.slice(0, max);
}

/**
 * Returns a URL that is safe to put into an <img src>, or null.
 * Allowed: same-origin paths, https, http on localhost (development), and image data URIs.
 */
export function safeMediaUrl(u) {
  if (typeof u !== "string" || u.length === 0 || u.length > MAX_MEDIA_URL) return null;
  if (/^data:image\/(svg\+xml|jpeg|png|webp)[;,]/.test(u)) return u;
  if (u.startsWith("/") && !u.startsWith("//")) return u;
  try {
    const url = new URL(u);
    if (url.protocol === "https:") return url.href;
    if (url.protocol === "http:" && (url.hostname === "localhost" || url.hostname === "127.0.0.1")) {
      return url.href;
    }
  } catch {
    return null;
  }
  return null;
}

const fail = (error) => ({ ok: false, error });

export function parseReport(raw) {
  if (!isObject(raw)) return fail("report is not an object");
  const { id, kind = "report", category, lat, lng, createdAt, severity = "minor", reporterId } = raw;
  if (!isId(id)) return fail("report.id");
  if (!REPORT_KINDS.includes(kind)) return fail("report.kind");
  if (!CATEGORY_IDS.has(category)) return fail("report.category");
  if (!isLatLng(lat, lng)) return fail("report.location");
  if (!isIso(createdAt)) return fail("report.createdAt");
  if (!SEVERITIES.includes(severity)) return fail("report.severity");
  if (!isId(reporterId)) return fail("report.reporterId");

  const v = isObject(raw.verification) ? raw.verification : { status: "pending" };
  if (!VERIFICATION_STATES.includes(v.status)) return fail("report.verification.status");
  const confidence =
    typeof v.confidence === "number" && v.confidence >= 0 && v.confidence <= 1 ? v.confidence : undefined;
  const reason = optionalText(v.reason, 200);
  if (reason === null) return fail("report.verification.reason");

  const note = optionalText(raw.note);
  if (note === null) return fail("report.note");
  const accuracyM =
    typeof raw.accuracyM === "number" && raw.accuracyM >= 0 && raw.accuracyM < 10_000 ? raw.accuracyM : undefined;
  const photoUrl = raw.photoUrl === undefined ? undefined : safeMediaUrl(raw.photoUrl);
  if (photoUrl === null) return fail("report.photoUrl");

  return {
    ok: true,
    value: {
      id,
      kind,
      category,
      lat,
      lng,
      accuracyM,
      createdAt: new Date(createdAt).toISOString(),
      severity,
      reporterId,
      verification: { status: v.status, confidence, reason },
      note,
      photoUrl,
    },
  };
}

function parseHistoryEntry(raw) {
  if (!isObject(raw)) return null;
  if (!STATUS_IDS.has(raw.status) || !isIso(raw.at)) return null;
  const by = HISTORY_ACTORS.includes(raw.by) ? raw.by : "sistema";
  const note = optionalText(raw.note);
  if (note === null) return null;
  return { status: raw.status, at: new Date(raw.at).toISOString(), by, note };
}

/**
 * Parses one case as served by `GET /cases`. Invalid reports and history entries are dropped and
 * counted in `dropped`; a case without at least one valid report is rejected.
 */
export function parseCase(raw) {
  if (!isObject(raw)) return fail("case is not an object");
  if (!isId(raw.id)) return fail("case.id");
  if (!CATEGORY_IDS.has(raw.category)) return fail("case.category");
  if (!STATUS_IDS.has(raw.status)) return fail("case.status");
  if (!isLatLng(raw.lat, raw.lng)) return fail("case.location");
  if (!Array.isArray(raw.reports)) return fail("case.reports");

  let dropped = 0;
  const reports = [];
  for (const r of raw.reports.slice(0, 500)) {
    const parsed = parseReport(r);
    if (parsed.ok && parsed.value.category === raw.category) reports.push(parsed.value);
    else dropped += 1;
  }
  if (reports.length === 0) return fail("case has no valid report");

  const history = [];
  for (const h of Array.isArray(raw.history) ? raw.history.slice(0, 200) : []) {
    const parsed = parseHistoryEntry(h);
    if (parsed) history.push(parsed);
    else dropped += 1;
  }

  const address = optionalText(raw.address, 160);
  const zone = optionalText(raw.zone, 60);
  if (address === null || zone === null) return fail("case.address");

  return {
    ok: true,
    value: {
      id: raw.id,
      category: raw.category,
      status: raw.status,
      lat: raw.lat,
      lng: raw.lng,
      address,
      zone,
      nearSensitive: raw.nearSensitive === true,
      reports,
      history,
      dropped,
    },
  };
}

/** Parses a `GET /cases` body: `{ cases: [...], serverTime }`. */
export function parseCaseList(body) {
  if (!isObject(body) || !Array.isArray(body.cases)) return fail("body.cases");
  const cases = [];
  let rejected = 0;
  for (const raw of body.cases.slice(0, 5000)) {
    const parsed = parseCase(raw);
    if (parsed.ok) cases.push(parsed.value);
    else rejected += 1;
  }
  const serverTime = isIso(body.serverTime) ? new Date(body.serverTime).toISOString() : undefined;
  return { ok: true, value: { cases, rejected, serverTime } };
}
