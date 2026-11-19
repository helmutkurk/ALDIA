// Case workflow. Modelled on the FixMyStreet idea of open / fixed / closed state groups, with one
// Aldia rule on top: a government user can never mark a case as fixed by hand. Only a verified
// "after" photo from a citizen closes it as fixed; if that photo shows the problem, it reopens.

export const STATUSES = Object.freeze({
  new: { label: "Nuevo", group: "open" },
  in_review: { label: "En revisión", group: "open" },
  scheduled: { label: "Programado", group: "open" },
  in_progress: { label: "En reparación", group: "open" },
  fix_claimed: { label: "Reparado, falta foto", group: "open" },
  reopened: { label: "Reabierto", group: "open" },
  fixed: { label: "Reparado y verificado", group: "fixed" },
  not_responsible: { label: "No corresponde", group: "closed" },
  duplicate: { label: "Duplicado", group: "closed" },
});

export const STATUS_IDS = new Set(Object.keys(STATUSES));

/** Changes a government user may make in the portal, by current status. */
export const MANUAL_TRANSITIONS = Object.freeze({
  new: ["in_review", "scheduled", "in_progress", "not_responsible", "duplicate"],
  in_review: ["scheduled", "in_progress", "not_responsible", "duplicate"],
  scheduled: ["in_progress", "not_responsible"],
  in_progress: ["fix_claimed", "scheduled"],
  fix_claimed: [],
  reopened: ["in_review", "scheduled", "in_progress"],
  fixed: [],
  not_responsible: ["in_review"],
  duplicate: ["in_review"],
});

export function statusLabel(id) {
  return STATUSES[id]?.label ?? id;
}

export function statusGroup(id) {
  return STATUSES[id]?.group ?? "open";
}

export function isOpen(id) {
  return statusGroup(id) === "open";
}

export function allowedTransitions(from) {
  return MANUAL_TRANSITIONS[from] ?? [];
}

export function canTransition(from, to) {
  return allowedTransitions(from).includes(to);
}

/**
 * Status after the verifier judged a citizen's "after" photo (kind `repair_check`).
 * Passed: the repair is proven, the case is fixed. Failed while the government claims a fix: reopened.
 */
export function statusAfterRepairCheck(current, passed) {
  if (passed && isOpen(current)) return "fixed";
  if (!passed && current === "fix_claimed") return "reopened";
  return current;
}
