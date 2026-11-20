/** Walk server pages in their stable API order, preserving the current filter. */
export async function getAdjacentReport(api, query, id, direction, signal) {
  let scanOffset = 0;
  let current = await api.getReports(
    { ...query(), offset: scanOffset },
    { signal },
  );
  let index = current.items.findIndex(
    (item) => item.id.toLowerCase() === id.toLowerCase(),
  );
  // A shared deep link may not belong to the first page. Search until found.
  while (index < 0 && scanOffset + 25 < current.total) {
    scanOffset += 25;
    current = await api.getReports(
      { ...query(), offset: scanOffset },
      { signal },
    );
    index = current.items.findIndex(
      (item) => item.id.toLowerCase() === id.toLowerCase(),
    );
  }
  if (index < 0) return null;
  if (current.items[index + direction])
    return current.items[index + direction].id;
  const nextOffset = scanOffset + direction * 25;
  if (nextOffset < 0 || nextOffset >= current.total) return null;
  const next = await api.getReports(
    { ...query(), offset: nextOffset },
    { signal },
  );
  return (direction > 0 ? next.items[0] : next.items.at(-1))?.id ?? null;
}
