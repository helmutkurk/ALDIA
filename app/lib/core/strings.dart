/// All user-facing text, Spanish (Guatemala). Move to ARB files when a second
/// language is needed.
class S {
  const S._();

  static const appName = 'Aldia';
  static const tagline =
      'Reporta problemas de tu calle con una foto verificada';

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
      'No pudimos obtener tu ubicación. Activa el permiso o elige el punto en el mapa.';
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
  static const statusVerifiedStub = 'Verificado (prueba)';
  static const statusRejected = 'Rechazado';
  static const resolutionOpen = 'Abierto';
  static const resolutionAcknowledged = 'En atención';
  static const resolutionFixed = 'Resuelto';

  static const emptyNearby = 'Todavía no hay reportes en esta zona.';
  static const emptyMine = 'Aún no has enviado reportes.';
  static const loadError = 'No se pudieron cargar los reportes.';
  static const reportDetail = 'Detalle del reporte';
  static const checks = 'Verificación';
  static const stubNotice =
      'Verificación de prueba: aún no se clasifica la foto.';
}
