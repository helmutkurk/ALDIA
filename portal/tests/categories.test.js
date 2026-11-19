// @vitest-environment node
import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';
import { CATEGORIES } from '../src/categories.js';

it('exactly mirrors category IDs and Spanish labels in the binding API contract', () => {
  const contract = readFileSync(
    new URL('../../documentation/api-contract.md', import.meta.url),
    'utf8',
  );
  const entries = [
    ...contract.matchAll(/^\| `([a-z_]+)` \| ([^|]+) \|$/gm),
  ].map(([, id, label]) => ({ id, label: label.trim() }));
  expect(entries).toHaveLength(6);
  expect(CATEGORIES).toEqual(entries);
  expect(new Set(CATEGORIES.map(({ id }) => id)).size).toBe(CATEGORIES.length);
});
