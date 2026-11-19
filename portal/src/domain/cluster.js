// Screen-space grid clustering for the map: points that fall in the same cell of `cellPx` pixels
// are drawn as one bubble with a count. Pure function so it is testable without a map library;
// the map view passes projected pixel coordinates in.

export function clusterPoints(points, cellPx) {
  const cells = new Map();
  for (const p of points) {
    const key = `${Math.floor(p.x / cellPx)}:${Math.floor(p.y / cellPx)}`;
    const cell = cells.get(key);
    if (cell) cell.members.push(p);
    else cells.set(key, { members: [p] });
  }
  return [...cells.values()].map(({ members }) => ({
    x: members.reduce((s, m) => s + m.x, 0) / members.length,
    y: members.reduce((s, m) => s + m.y, 0) / members.length,
    members,
  }));
}
