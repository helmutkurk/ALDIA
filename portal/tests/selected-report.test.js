import { afterEach, expect, it, vi } from 'vitest';
import { createSelection } from '../src/selected-report.js';
import { municipalReport } from './fixtures.js';
let selection;
afterEach(() => {
  selection?.clear();
  document.body.replaceChildren();
});
it('recovers from detail errors and restores keyboard focus when closed', async () => {
  const row = document.createElement('button');
  const side = document.createElement('section');
  document.body.append(row, side);
  const api = {
    getReport: vi
      .fn()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce(municipalReport()),
  };
  selection = createSelection(side, {
    api,
    staff: null,
    getScope: () => ({}),
    onSaved: vi.fn(),
  });
  row.focus();
  await selection.showReport(municipalReport().id);
  expect(side.querySelector('[role="alert"]')).not.toBeNull();
  side.querySelector('.retry-button').click();
  for (let i = 0; i < 5; i++) await Promise.resolve();
  expect(side.querySelector('h2').textContent).toBe('Bache');
  expect(document.activeElement.tagName).toBe('H2');
  side.querySelector('button').click();
  expect(side.childElementCount).toBe(0);
  expect(document.activeElement).toBe(row);
});
