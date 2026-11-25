import { expect, it } from 'vitest';
import { cityBounds } from '../src/main.js';

it('keeps a linked view of Guatemala City', () => {
  const bbox = [-90.57, 14.59, -90.44, 14.7];
  expect(cityBounds(bbox)).toBe(bbox);
});

it('drops a linked view of the whole country or another place', () => {
  expect(cityBounds([-92.2, 13.7, -88.2, 17.8])).toBeUndefined();
  expect(cityBounds([-91.6, 14.8, -91.4, 15.0])).toBeUndefined();
  expect(cityBounds(undefined)).toBeUndefined();
});
