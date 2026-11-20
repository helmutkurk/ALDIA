import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const css = readFileSync('src/styles/tokens.css', 'utf8');
const tokens = Object.fromEntries(
  [...css.matchAll(/--([\w-]+):\s*([^;]+);/g)].map(([, name, value]) => [
    name,
    value.trim(),
  ]),
);
const color = (name) => {
  const value = tokens[name];
  const alias = /^var\(--([\w-]+)\)$/.exec(value);
  return alias ? color(alias[1]) : value;
};
// WCAG relative luminance: linearize sRGB channels before weighting them.
const luminance = (hex) => {
  const channels = hex
    .slice(1)
    .match(/../g)
    .map((channel) => {
      const srgb = parseInt(channel, 16) / 255;
      return srgb <= 0.04045 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4;
    });
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
};
const contrast = (foreground, background) => {
  const values = [foreground, background].map((name) => luminance(color(name)));
  return (Math.max(...values) + 0.05) / (Math.min(...values) + 0.05);
};

const pairs = [
  ...[
    'text',
    'text-muted',
    'primary-dark',
    'danger',
    'success',
    'series-received',
    'series-resolved',
  ].flatMap((foreground) =>
    ['surface', 'background'].map((background) => [foreground, background]),
  ),
  ['primary', 'surface'],
  ['on-primary', 'primary'],
  ['on-primary', 'primary-dark'],
  ['on-bar', 'bar'],
  ['text', 'border'],
];
// Status colors are dot, pin and series fills (non-text): at least 3:1 on
// white; the status word beside them always uses the normal text color.
const dots = ['state-open', 'state-work', 'state-resolved', 'state-closed'];

describe('calm palette text contrast', () => {
  it('uses the WCAG luminance endpoints', () => {
    expect(luminance('#000000')).toBe(0);
    expect(luminance('#ffffff')).toBe(1);
  });
  it.each(pairs)('%s on %s is at least 4.5:1', (foreground, background) => {
    expect(contrast(foreground, background)).toBeGreaterThanOrEqual(4.5);
  });
  it.each(dots)('%s dot is at least 3:1 on the surface', (name) => {
    expect(contrast(name, 'surface')).toBeGreaterThanOrEqual(3);
  });
  it('white pin outline separates pins from the map halo', () => {
    expect(contrast('text', 'surface')).toBeGreaterThanOrEqual(4.5);
  });
});
