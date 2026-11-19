/** Neutral SVG fills. Unique ids keep multiple charts independent on one page. */
const SVG = 'http://www.w3.org/2000/svg';
let chartId = 0;

export function chartPatterns(svg) {
  const defs = document.createElementNS(SVG, 'defs');
  const prefix = `chart-pattern-${++chartId}`;
  const fills = { solid: 'var(--primary)', outline: 'var(--surface)' };
  for (const [kind, path] of Object.entries({
    diagonal: 'M-2 2L2 -2M0 8L8 0M6 10L10 6',
    horizontal: 'M0 4H8',
    cross: 'M0 4H8M4 0V8',
    dots: null,
  })) {
    const pattern = document.createElementNS(SVG, 'pattern');
    pattern.id = `${prefix}-${kind}`;
    pattern.setAttribute('width', '8');
    pattern.setAttribute('height', '8');
    pattern.setAttribute('patternUnits', 'userSpaceOnUse');
    const background = document.createElementNS(SVG, 'rect');
    background.setAttribute('width', '8');
    background.setAttribute('height', '8');
    background.setAttribute('fill', 'var(--surface)');
    const mark = document.createElementNS(SVG, path ? 'path' : 'circle');
    if (path) {
      mark.setAttribute('d', path);
      mark.setAttribute('stroke', 'var(--primary)');
      mark.setAttribute('fill', 'none');
    } else {
      mark.setAttribute('cx', '4');
      mark.setAttribute('cy', '4');
      mark.setAttribute('r', '1.5');
      mark.setAttribute('fill', 'var(--primary)');
    }
    pattern.append(background, mark);
    defs.append(pattern);
    fills[kind] = `url(#${pattern.id})`;
  }
  svg.append(defs);
  return fills;
}
