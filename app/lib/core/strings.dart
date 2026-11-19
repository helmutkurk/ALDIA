/// All user-facing text, Spanish (Guatemala). Move to ARB files when a second
/// language is needed.
class S {
  const S._();

  static const appName = 'Aldia';
  static const tagline =
      'Reporta problemas de tu calle con una foto verificada';

  static const onboardingSkip = 'Omitir';
  static const onboardingStart = 'Empezar';
  static const onboardingTitles = [
    'Reporta lo que ves en tu calle',
    'La foto se toma en el momento',
    'Tu privacidad',
  ];
  static const onboardingBodies = [
    'Baches, aceras, luminarias y más. Envías una foto y el punto en el mapa; el municipio da seguimiento.',
    'Toma la foto desde la acera, justo donde está el problema. No se aceptan fotos de la galería ni de personas.',
    'La foto y el punto del reporte son públicos. No necesitas cuenta; no pedimos tu nombre ni tu teléfono.',
  ];
  static String onboardingPage(int current, int total) =>
      'Página $current de $total';
  static const emptyNearbyHelp =
      'Si ves un problema, sé la primera persona en reportarlo.';
  static const navMap = 'Mapa';
  static const navList = 'Lista';
  static const myReports = 'Mis reportes';
  static const newReport = 'Reportar';
  static const retry = 'Reintentar';
  static const cancel = 'Cancelar';
  static const back = 'Atrás';
  static const next = 'Siguiente';
  static const send = 'Enviar reporte';
  static const close = 'Cerrar';

  static const stepLocation = 'Ubicación';
  static const stepCategory = 'Categoría';
  static const stepPhoto = 'Foto';
  static const stepNote = 'Detalles';

  static const locationHint = 'Toca el mapa para mover el punto del problema.';
  static const useMyLocation = 'Usar mi ubicación';
  static const locationDenied =
      'Permiso de ubicación denegado. Puedes elegir el punto en el mapa.';
  static const chooseCategory = 'Qué tipo de problema es';
  static const takePhoto = 'Tomar foto';
  static const retakePhoto = 'Tomar otra foto';
  static const photoRequired =
      'La foto se toma en el momento, desde la acera. No fotografíes personas.';
  static const noteLabel = 'Descripción (opcional)';
  static const noteHint = 'Ej. Hueco grande frente a la escuela';

  static const sending = 'Enviando…';
  static const resultVerified = 'Reporte verificado';
  static const resultRejected = 'La foto no pasó la verificación';
  static const resultPending = 'Reporte recibido, verificación pendiente';
  static const resultRejectedHelp = 'Revisa los motivos y toma otra foto.';
  static const sendError = 'No se pudo enviar el reporte. Revisa tu conexión.';

  static const statusPending = 'Pendiente';
  static const statusVerified = 'Verificado';
  static const statusRejected = 'Rechazado';

  static const emptyNearby = 'Todavía no hay reportes en esta zona.';
  static const emptyMine =
      'Aún no tienes reportes. El primero que envíes aparecerá aquí.';
  static const apply = 'Aplicar';
  static const firstReport = 'Hacer mi primer reporte';
  static const emptyFiltered = 'No hay reportes con estos filtros.';
  static const clearFilters = 'Quitar filtros';
  static const sentReports = 'Enviados';
  static const retryNow = 'Reenviar ahora';
  static const outboxWillRetry = 'Se enviará solo cuando vuelva la conexión.';
  static const deleteOutboxQuestion =
      '¿Eliminar este reporte sin enviar? Se perderá su foto.';
  static const draftBannerHelp = 'Tienes un reporte sin terminar.';
  static const mapFallback =
      'No se pudo cargar la agrupación del mapa; se muestran reportes sueltos.';
  static const pinReport = 'Reporte';
  static const zoomToCluster = 'Acercar para ver los reportes';
  static const filtersLabel = 'Filtros de reportes';
  static const duplicateOfTitle = 'Ya está reportado';
  static const viewMainReport = 'Ver el reporte principal';
  static const officialMessage = 'Mensaje del municipio';
  static const received = 'Recibido';
  static const loadError = 'No se pudieron cargar los reportes.';
  static const reportDetail = 'Detalle del reporte';
  static const checks = 'Verificación';
  static const stubNotice =
      'Verificación de prueba: aún no se clasifica la foto.';

  static const stepDuplicates = '¿Ya está reportado?';
  static const stepReview = 'Revisar y enviar';
  static const usePhoto = 'Usar esta foto';
  static const differentProblem = 'Es un problema distinto';
  static const followReport = 'Seguir este reporte';
  static const following = 'Reporte guardado en Mis reportes';
  static const changeCategory = 'Cambiar categoría';
  static const adjustLocation = 'Ajustar ubicación';
  static const openSettings = 'Abrir ajustes';
  static const locationDeniedForever =
      'Permiso denegado para siempre. Abre ajustes o elige el punto en el mapa.';
  static const locationServiceOff =
      'GPS apagado. Actívalo o elige el punto en el mapa.';
  static const locationUnavailable =
      'No hay señal de ubicación. Elige el punto en el mapa.';
  static const poorAccuracy =
      'La precisión supera 50 m. Reintenta el GPS o ajusta el punto en el mapa.';
  static const confirmLocation = 'Confirmar ubicación';
  static const locating = 'Buscando ubicación…';
  static const edit = 'Editar';
  static const manualReview = 'Enviar para revisión manual';
  static const manualSaved =
      'Reporte guardado en este dispositivo. La revisión manual aún no está disponible.';
  static const waitingNetwork = 'Esperando red';
  static const waitingNetworkHelp =
      'Reporte guardado. Se enviará automáticamente cuando vuelva la conexión. Si se retrasa, el servidor comprobará la fecha original de la foto.';
  static const draft = 'Borrador';
  static const continueDraft = 'Continuar borrador';
  static const savedDrafts = 'Borradores';
  static const outbox = 'Por enviar';
  static const missingPhoto =
      'La foto guardada ya no está. Toma otra foto; los demás datos se conservan.';
  static const photoError =
      'No se pudo abrir la cámara. Revisa el permiso de cámara e inténtalo de nuevo.';
  static const storageError =
      'No se pudo guardar en el dispositivo. Revisa el espacio disponible antes de salir.';
  static const deleteDraft = 'Eliminar borrador';
  static const deleteDraftQuestion = '¿Eliminar este borrador y su foto?';
  static const delete = 'Eliminar';
  static const timeline = 'Historial';
  static const nearbyHint = 'Hay reportes similares cerca de este punto.';
  static const duplicateHint =
      'Este reporte está vinculado a otro sobre el mismo problema.';
  static const allStates = 'Todos los estados';
  static const allCategories = 'Todas las categorías';
  static const filterState = 'Estado';
  static const filterCategory = 'Categoría';
  static const viewDetail = 'Ver detalle';
  static const photoAlternative = 'Foto del problema reportado';
  static const mapAlternative =
      'Mapa de reportes. Usa Lista para consultar sin el mapa.';
  static const pinAlternative =
      'Punto del problema. Toca el mapa para ajustarlo.';
  static const confirmPinHint =
      'También puedes ajustar latitud y longitud sin usar el mapa.';
  static const latitude = 'Latitud';
  static const longitude = 'Longitud';
  static const coordinatesInvalid = 'Introduce coordenadas válidas.';
  static const applyCoordinates = 'Usar estas coordenadas';
  static const pendingHelp =
      'Guardado, verificación pendiente. Puedes consultar las novedades en Mis reportes.';
  static const publicPhotoNotice =
      'La foto y el punto del reporte serán públicos. Evita incluir personas o datos privados.';
  static String reference(String id) => 'Referencia: $id';
  static String uploadSize(int bytes) =>
      'Tamaño estimado de envío: ${(bytes / 1024).ceil()} KB';
  static String age(DateTime created, DateTime now) {
    final d = now.difference(created);
    if (d.inDays > 0) return 'Hace ${d.inDays} días';
    if (d.inHours > 0) return 'Hace ${d.inHours} h';
    return 'Hace ${d.inMinutes.clamp(0, 59)} min';
  }

  static String accuracy(double value) => 'Precisión GPS: ${value.round()} m';
  static String clusterCount(int count) => '$count reportes';
  static String stepProgress(int current, int total) =>
      'Paso $current de $total';
  static String photoLabel(String category, String state) =>
      'Foto: $category. $state';
  static const checkTitles = {
    'place': 'Ubicación de la foto',
    'freshness': 'Fecha de la foto',
    'duplicate': 'Reporte similar',
    'category': 'Categoría de la foto',
    'image': 'Calidad de la foto',
  };
  static const checkPassed = 'Comprobación completada';
  static const checkUnknown = 'No se pudo comprobar la foto';
  static const checkUnknownFix = 'Toma otra foto e inténtalo de nuevo.';
  static const placeReason = 'La foto parece tomada lejos del punto marcado.';
  static const placeFix = 'Acércate al problema o ajusta el punto en el mapa.';
  static const freshnessReason = 'La foto es demasiado antigua.';
  static const freshnessFix = 'Toma una foto nueva ahora.';
  static const duplicateReason = 'Ya existe un reporte similar aquí.';
  static const duplicateFix =
      'Consulta el reporte cercano y síguelo si es el mismo problema.';
  static String categoryReason(String category) =>
      'La foto no parece mostrar: $category.';
  static const categoryFix =
      'Cambia la categoría o toma otra foto que muestre el problema.';
  static const imageReason =
      'No se pudo leer la foto o no tiene suficiente detalle.';
  static const imageFix = 'Toma otra foto con buena luz y el problema visible.';
}
