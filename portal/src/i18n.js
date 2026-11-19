/** Spanish UI copy. API-provided content is displayed verbatim as text. */
export const t = Object.freeze({
  appName: 'Aldia',
  noScript: 'Activa JavaScript para consultar los reportes en el mapa.',
  portalTitle: 'Reportes ciudadanos',
  city: 'Ciudad de Guatemala',
  introduction: 'Explora los reportes de la zona visible en el mapa.',
  skipToReports: 'Ir a los reportes',
  mapLabel: 'Mapa de reportes ciudadanos',
  mapHelp: 'Usa las flechas para mover el mapa y + o − para acercar o alejar.',
  mapTilesError:
    'No se pudo cargar el mapa base. Los reportes siguen disponibles en la lista.',
  filters: 'Filtrar reportes',
  resolution: 'Atención del reporte',
  allResolutions: 'Todos los estados de atención',
  resolutions: Object.freeze({
    open: 'Abierto',
    acknowledged: 'En atención',
    fixed: 'Resuelto',
  }),
  mapView: 'Explorar mapa',
  dashboard: 'Panel de reportes',
  downloadCsv: 'Descargar CSV',
  dashboardScope: 'Reportes de la zona y los filtros seleccionados en el mapa.',
  dashboardLoading: 'Cargando estadísticas…',
  dashboardError: 'No se pudieron cargar las estadísticas.',
  totalReports: (total) => `Total de reportes: ${total}`,
  byCategory: 'Por categoría',
  byStatus: 'Por verificación',
  byResolution: 'Por atención',
  backToMap: 'Volver al mapa',
  viewReport: 'Ver reporte completo',
  reportLoading: 'Cargando reporte…',
  reportNotFound: 'No se encontró el reporte.',
  reportError: 'No se pudo cargar el reporte.',
  pageNotFound: 'No se encontró la página.',
  location: 'Ubicación del reporte',
  placeSearch: 'Busca un lugar',
  placePlaceholder: 'Ciudad, barrio o dirección',
  search: 'Buscar',
  searchHelp:
    'Escribe un lugar de Guatemala, Colombia o México y pulsa Buscar.',
  searchLoading: 'Buscando lugares…',
  searchEmpty: 'No se encontraron lugares. Prueba con otro nombre.',
  searchError: 'No se pudo buscar el lugar. Vuelve a pulsar Buscar.',
  placeResults: 'Lugares encontrados',
  placeCount: (count) =>
    `${count} lugares encontrados. Usa la flecha abajo o Tab para elegir.`,
  searchAttribution: 'Búsqueda © OpenStreetMap',
  category: 'Categoría',
  allCategories: 'Todas las categorías',
  status: 'Estado',
  allStatuses: 'Todos los estados',
  statuses: Object.freeze({
    verified: 'Verificado',
    rejected: 'Rechazado',
    pending: 'Pendiente',
  }),
  markerLetters: Object.freeze({ verified: 'V', rejected: 'R', pending: 'P' }),
  reports: 'Reportes en esta zona',
  loading: 'Cargando reportes…',
  empty: 'No hay reportes en esta zona con estos filtros.',
  emptyHelp: 'Mueve el mapa o cambia los filtros para explorar otra zona.',
  errorTitle: 'No se pudieron cargar los reportes.',
  retry: 'Volver a intentar',
  zoomIn: 'Acercar',
  zoomOut: 'Alejar',
  closePopup: 'Cerrar detalle',
  capturedAt: 'Capturado (hora de Guatemala)',
  unknownDate: 'Fecha no disponible',
  photoAlt: (category) => `Foto del reporte: ${category}`,
  photoUnavailable: 'Foto no disponible.',
  verification: 'Comprobaciones de verificación',
  verificationPending: 'Verificación pendiente.',
  stubWarning: 'Verificación de prueba: no es una verificación real.',
  stubSuffix: ' (prueba)',
  modelVerification: 'Verificación automática',
  passed: 'Superada',
  failed: 'No superada',
  noChecks: 'No hay comprobaciones disponibles.',
  checks: Object.freeze({
    image: 'Imagen',
    place: 'Ubicación',
    freshness: 'Antigüedad',
    category: 'Categoría',
    duplicate: 'Duplicados',
  }),
  networkError:
    'No se pudo conectar con el servidor. Comprueba tu conexión e inténtalo de nuevo.',
  timeoutError: 'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
  invalidResponse:
    'El servidor devolvió una respuesta no válida. Inténtalo de nuevo.',
  httpError: (status) =>
    `El servidor devolvió un error (${status}). Inténtalo de nuevo.`,
  count: (shown, total) => `${shown} de ${total} reportes`,
  limitHint:
    'Se muestran hasta 500 reportes, del más reciente al más antiguo. Acerca el mapa o filtra para ver menos resultados.',
  selectReport: (category, status) => `Ver en el mapa: ${category}. ${status}.`,
});

export const RESOLUTIONS = Object.freeze(Object.keys(t.resolutions));

export const STATUSES = Object.freeze(Object.keys(t.statuses));

/** @param {import('./api.js').Report} report */
export function statusLabel(report) {
  return (
    t.statuses[report.status] +
    (report.verification?.mode === 'stub' ? t.stubSuffix : '')
  );
}

const dateFormatter = new Intl.DateTimeFormat('es-GT', {
  dateStyle: 'medium',
  timeStyle: 'short',
  timeZone: 'America/Guatemala',
});

/** @param {string} value */
export function formatDate(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? t.unknownDate
    : dateFormatter.format(date);
}
