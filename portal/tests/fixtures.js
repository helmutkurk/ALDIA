/** Synthetic report data; no real people or photographs. */
export function report(overrides = {}) {
  return {
    id: '12345678-1234-4234-8234-123456789abc',
    category: 'pothole',
    latitude: 14.6349,
    longitude: -90.5069,
    captured_at: '2026-11-19T18:30:00Z',
    created_at: '2026-11-19T18:30:05Z',
    status: 'verified',
    resolution: 'open',
    note: null,
    photo_url: '/api/reports/12345678-1234-4234-8234-123456789abc/photo',
    verification: {
      passed: true,
      mode: 'stub',
      checks: [{ name: 'freshness', passed: true, detail: 'age 5 s' }],
    },
    ...overrides,
  };
}

/** Additive municipal fixture, independent of legacy report tests. */
export function municipalReport(overrides = {}) {
  return report({
    state: 'en_revision',
    state_group: 'open',
    state_changed_at: '2026-11-19T19:00:00Z',
    verified_at: '2026-11-19T18:30:10Z',
    resolved_at: null,
    closed_at: null,
    assignee: null,
    duplicate_of: null,
    public_note: null,
    events: [],
    ...overrides,
  });
}
