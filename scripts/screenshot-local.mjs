#!/usr/bin/env node
// Run outside the Codex sandbox, with an already installed Playwright module.
import { mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(new URL('../portal/package.json', import.meta.url));
let chromium;
try {
  ({ chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright'));
} catch {
  console.error(
    'Use an existing Playwright installation outside the sandbox; set PLAYWRIGHT_MODULE to its absolute module path if needed.',
  );
  process.exit(1);
}
const shots = new URL('../.local/shots/', import.meta.url);
await mkdir(shots, { recursive: true });
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  await page.goto('http://127.0.0.1:5173/', { waitUntil: 'domcontentloaded' });
  await page.locator('#map.leaflet-container').waitFor();
  await page.locator('#map .leaflet-marker-icon').first().waitFor();
  await page.locator('.report-list li').first().waitFor();
  const path = fileURLToPath(new URL('portal.png', shots));
  await page.screenshot({ path, fullPage: true });
  console.log(`Map and report list loaded; screenshot saved to ${path}`);
} finally {
  await browser.close();
}
