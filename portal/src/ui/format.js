// Spanish (Guatemala) formatting. Times are shown in Guatemala's time zone.

const TZ = "America/Guatemala";
const dateTime = new Intl.DateTimeFormat("es-GT", { dateStyle: "medium", timeStyle: "short", timeZone: TZ });
const oneDecimal = new Intl.NumberFormat("es-GT", { maximumFractionDigits: 1, minimumFractionDigits: 1 });

export function relativeTime(iso, now) {
  const minutes = Math.round((now - Date.parse(iso)) / 60_000);
  if (minutes < 1) return "hace un momento";
  if (minutes < 60) return `hace ${minutes} min`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `hace ${hours} h`;
  const days = Math.round(hours / 24);
  return days === 1 ? "hace 1 día" : `hace ${days} días`;
}

export function formatDateTime(iso) {
  return dateTime.format(new Date(iso));
}

export function formatDays(days) {
  if (days === undefined || Number.isNaN(days)) return "—";
  if (days < 1) return `${Math.max(1, Math.round(days * 24))} h`;
  return `${oneDecimal.format(days)} días`;
}

export function plural(n, one, many) {
  return `${n} ${n === 1 ? one : many}`;
}
