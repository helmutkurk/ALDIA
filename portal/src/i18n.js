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
    closed: 'Cerrado',
  }),
  mapView: 'Explorar mapa',
  dashboard: 'Panel de reportes',
  dash: Object.freeze({
    delimiter: 'Separador CSV',
    comma: 'Coma',
    semicolon: 'Punto y coma',
    unavailable: 'Sin datos',
    hours: 'h',
    sample: (n) => `n = ${n}`,
    recibidos: 'Recibidos',
    rechazados_verificador: 'Rechazados por verificador',
    abiertos: 'Abiertos',
    resueltos: 'Resueltos',
    cerrados_sin_solucion: 'Cerrados sin solución',
    tasa_resolucion: 'Tasa de resolución',
    median: 'Mediana de resolución',
    p90: 'p90 de resolución',
    mean: 'Media de resolución',
    first: 'Primera respuesta: mediana',
    firstP90: 'Primera respuesta: p90',
    sla_cumplido: 'SLA cumplido',
    vencidos: 'Vencidos',
    ages: 'Antigüedad de abiertos',
    days: 'días',
    categoryGroups: 'Categoría y grupo de estado',
    categoryRepair: 'Tiempo de reparación por categoría',
    categoryRepairNote:
      'Reportes creados en el periodo consultado y actualmente resueltos. Horas desde la verificación hasta la resolución; n indica cuántos tienen ambas fechas. Las barras muestran la mediana.',
    categoryFrequency: 'Frecuencia por categoría',
    categoryFrequencyNote:
      'Estado actual de los reportes creados en el periodo consultado. Abiertos incluye pendientes de verificación y en trabajo; cerrados incluye rechazos del verificador.',
    categoryBuckets: Object.freeze({
      resueltos: 'Resueltos',
      abiertos: 'Abiertos',
      cerrados: 'Cerrados',
    }),
    repairSamples: 'Muestras (n)',
    seeTable: 'Ver tabla',
    seeTableFor: (title) => `Ver tabla: ${title}`,
    repairDescription: (category, median, p90, n) =>
      `${category}: mediana ${median}; p90 ${p90}; n = ${n}`,
    frequencyDescription: (category, row) =>
      `${category}: Total: ${row.total} · Resueltos: ${row.resueltos} · Abiertos: ${row.abiertos} · Cerrados: ${row.cerrados}`,
    kpiStrip: 'Resumen de indicadores',
    groups: Object.freeze({
      pending: 'Pendientes',
      open: 'Abiertos',
      in_work: 'En trabajo',
      resolved: 'Resueltos',
      closed: 'Cerrados',
      hidden: 'Ocultos',
    }),
    weekly: 'Recibidos y resueltos por semana',
    allTime: 'Acumulado en el periodo consultado',
    allTimeNote:
      'Suma semanal de los reportes recibidos y resueltos que cumplen los filtros.',
    receivedLabel: 'reportes recibidos',
    resolvedLabel: 'reportes resueltos',
    lastWeek: 'Última semana',
    lastWeekNote: (week) =>
      `Semana ${week}; la línea muestra las últimas semanas disponibles.`,
    sparkLabel: (name, values) => `${name}, últimas semanas: ${values}`,
    topCategories: 'Las 5 categorías con más reportes',
    noCategories: 'No hay reportes por categoría en este periodo.',
    zone: 'Zona consultada',
    zoneChange: 'Cambiar zona en el mapa',
    indicators: 'Indicadores',
    exportData: 'Exportar datos',
    weeklyLegend: 'Recibidos: línea continua. Resueltos: línea discontinua.',
    distribution: 'Distribución por grupo',
    week: 'Semana',
    total: 'Total',
    noWeeks: 'No hay semanas con datos en este periodo.',
    metricsNote:
      'La tasa excluye duplicados y fuera de competencia del denominador. Los tiempos se calculan desde la verificación; las resoluciones solo incluyen casos resueltos. Fechas según America/Guatemala.',
    filterLimits:
      'Los enlaces de categorías y grupos abren la lista filtrada. La API aún no ofrece filtros exactos para antigüedad, SLA, primera respuesta ni fecha de resolución; esas métricas no tienen un enlace equivalente.',
    zoneLimits: 'La API aún no ofrece desglose por zona.',
    crossError:
      'No se pudo cargar el desglose por categoría. Vuelve a intentar.',
  }),
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
  status: 'Resultado del verificador',
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
  heuristicVerification:
    'Verificación técnica automática (lugar, hora, nitidez, exposición). No clasifica el tipo de problema.',
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
  hour12: false,
  timeZone: 'America/Guatemala',
});

/** @param {string} value */
export function formatDate(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? t.unknownDate
    : dateFormatter.format(date);
}

/** Staff and v0.2 UI copy; kept separate from the legacy dictionary. */
export const ui = Object.freeze({
  states: {
    pendiente_verificacion: 'Pendiente de verificación',
    rechazado_verificador: 'Rechazado por verificador',
    nuevo: 'Nuevo',
    en_revision: 'En revisión',
    programado: 'Programado',
    en_proceso: 'En proceso',
    resuelto: 'Resuelto',
    no_procede: 'No procede',
    fuera_de_competencia: 'Fuera de competencia',
    duplicado: 'Duplicado',
    oculto: 'Oculto',
  },
  groups: {
    pending: 'Pendiente',
    open: 'Abiertos',
    in_work: 'En trabajo',
    resolved: 'Resueltos',
    closed: 'Cerrados',
    hidden: 'Ocultos',
  },
  groupLetters: {
    pending: 'P',
    open: 'A',
    in_work: 'T',
    resolved: 'R',
    closed: 'C',
    hidden: 'O',
  },
  staff: 'Modo personal',
  username: 'Usuario',
  password: 'Contraseña',
  login: 'Iniciar sesión',
  logout: 'Cerrar sesión',
  loginHelp: 'Accede con tu cuenta de personal. La sesión dura hasta 12 horas.',
  authLoading: 'Comprobando sesión…',
  devTokens: 'Acceso de desarrollo con token',
  signedIn: (user) => `${user.username} · ${ui[user.role]}`,
  forbidden:
    'No tienes permisos para esta acción. Si acabas de iniciar sesión, recarga la página y vuelve a intentarlo.',
  locked:
    'Cuenta bloqueada durante 15 minutos por intentos fallidos. Espera antes de volver a intentar.',
  rateLimited:
    'Demasiados intentos de acceso. Espera 15 minutos y vuelve a intentarlo.',
  token: 'Token de personal',
  enable: 'Activar',
  disable: 'Salir del modo personal',
  staffHelp:
    'El token permanece solo en memoria hasta recargar o cerrar esta pestaña. El servidor verifica los permisos en cada acción.',
  role: 'Permisos solicitados',
  operator: 'Operador',
  supervisor: 'Supervisor',
  admin: 'Administrador',
  roleHelp:
    'Seleccionar supervisor no concede permisos: requiere el token de supervisor.',
  publicMode: 'Vista pública de solo lectura',
  staffActive: 'Modo personal activo',
  tokenLength: 'El token debe tener al menos 32 caracteres.',
  state: 'Estado municipal',
  stateGroup: 'Grupo de estados',
  allStates: 'Todos los estados municipales',
  allGroups: 'Todos los grupos',
  from: 'Desde',
  to: 'Hasta',
  assignee: 'Cuadrilla o responsable',
  sort: 'Ordenar',
  sorts: {
    newest: 'Más recientes',
    oldest: 'Más antiguos',
    updated: 'Última actualización',
    age_in_state: 'Antigüedad en el estado',
  },
  includeOld: 'Incluir antiguos',
  includeOldLong: 'Incluir reportes antiguos',
  statusFilter: 'Estado',
  moreFilters: 'Más filtros',
  mainNav: 'Principal',
  brandTagline: 'Portal de gobierno',
  municipality: 'Municipio',
  kpiLabel: 'Resumen de la zona del mapa',
  kpiOpen: 'Abiertos',
  kpiWork: 'En trabajo',
  kpiResolved: 'Resueltos',
  kpiMedian: 'Mediana de reparación',
  navMap: 'Mapa',
  navTriage: 'Triaje',
  navDashboard: 'Panel',
  navStaff: 'Modo personal',
  panelBanner: 'Gobierno municipal',
  range: (from, to, total) =>
    from === to
      ? `${from} de ${total} reportes`
      : `${from} a ${to} de ${total} reportes`,
  showMap: 'Ver mapa',
  showList: 'Ver lista',
  thumbnail: 'Miniatura del reporte',
  defaultWindow: 'Por defecto: últimos 90 días.',
  removeFilter: (label) => `Quitar filtro: ${label}`,
  previous: 'Anterior',
  next: 'Siguiente',
  page: (page, total) =>
    `Página ${page} de ${Math.max(1, Math.ceil(total / 25))}`,
  mapToggle: 'Mostrar u ocultar mapa',
  selected: 'Reporte seleccionado',
  cluster: (n) => `${n} reportes; acercar para verlos`,
  clusterReports: (n) => `Reportes del grupo (${n})`,
  clusterLimited:
    'El servidor solo identifica hasta cinco reportes del grupo. La lista de la zona permite continuar la consulta.',
  clusterError: 'No se pudieron cargar los grupos del mapa.',
  transition: 'Cambiar estado',
  nextState: 'Nuevo estado',
  publicNote: 'Nota pública',
  internalNote: 'Nota interna',
  reasonRequired:
    'Este cambio requiere una razón en la nota pública o interna.',
  internalRequired: 'La anulación del rechazo requiere una nota interna.',
  noTransitions: 'No hay cambios de estado disponibles para estos permisos.',
  duplicateOf: 'Reporte principal (UUID)',
  invalidDuplicate: 'Indica el UUID de otro reporte principal.',
  save: 'Guardar',
  saved: 'Cambio guardado.',
  assign: 'Asignar',
  unassigned: 'Sin asignar',
  conflict:
    'El reporte cambió o la transición no está permitida. Recarga el reporte y revisa el estado actual.',
  unauthorized:
    'La sesión caducó o las credenciales no son válidas. Inicia sesión de nuevo.',
  unavailable:
    'El modo personal no está disponible en el servidor. Contacta con la administración.',
  timeline: 'Historial de estados',
  noEvents: 'No hay eventos registrados.',
  created: 'Creado',
  verified: 'Verificado',
  changed: 'Estado actualizado',
  coordinates: 'Coordenadas',
  actors: {
    system: 'Sistema',
    operator: 'Operador',
    supervisor: 'Supervisor',
    admin: 'Administrador',
  },
  zoomPhoto: 'Ampliar foto',
  closePhoto: 'Cerrar foto ampliada',
  nearby: 'Posibles duplicados cercanos',
  noNearby: 'No hay reportes cercanos compatibles.',
  nearbyError: 'No se pudieron consultar los posibles duplicados.',
  markDuplicate: 'Marcar como duplicado',
  duplicateHelp:
    'Para marcar un duplicado, lleva primero el reporte a En revisión.',
  triage: 'Bandeja de revisión',
  review: 'Por revisar',
  rejected: 'Rechazadas por verificador',
  age: (hours) => `${Math.floor(hours)} h desde la verificación`,
  queueError: 'No se pudo cargar la bandeja.',
  staffNeeded: 'Inicia sesión en Modo personal para gestionar la bandeja.',
  override: 'Anular rechazo',
  refresh: 'Recargar reporte',
});

/** Stable Spanish guidance for action failures; server text remains literal data. @param {object} error */
export function staffError(error) {
  return (
    {
      401: ui.unauthorized,
      403: ui.forbidden,
      423: ui.locked,
      429: ui.rateLimited,
      409: ui.conflict,
      503: ui.unavailable,
    }[error.status] ??
    error.error?.message ??
    t.networkError
  );
}
