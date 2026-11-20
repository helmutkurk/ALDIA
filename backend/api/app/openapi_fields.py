"""Spanish schema field descriptions and documented error examples."""

from app.openapi_examples import AT, CHECKS, DEMO_ID, EVENTS, VERIFICATION

FIELD_DOCS: dict[str, tuple[str, object]] = {
    "id": ("Identificador estable del reporte o usuario.", DEMO_ID),
    "created_at": ("Fecha y hora de recepción en UTC.", AT),
    "state_changed_at": ("Fecha del último cambio de estado.", AT),
    "verified_at": ("Fecha de respuesta del verificador; null si está pendiente.", AT),
    "resolved_at": ("Fecha de resolución; null si aún no está resuelto.", None),
    "closed_at": ("Fecha de cierre sin solución; null si no corresponde.", None),
    "assigned_at": ("Fecha de la asignación actual; null si nunca se asignó.", None),
    "duplicate_of": ("UUID del reporte principal si es un duplicado.", None),
    "events": (
        "Historial de cambios, del más antiguo al más reciente.",
        EVENTS,
    ),
    "at": ("Fecha y hora del evento con zona horaria.", AT),
    "from_state": (
        "Estado anterior; null al crear el reporte.",
        "pendiente_verificacion",
    ),
    "to_state": ("Estado tras el cambio.", "nuevo"),
    "actor_role": ("Rol que realizó el cambio.", "system"),
    "passed": ("Indica si pasó la comprobación o la verificación.", True),
    "mode": ("Modo del verificador; heuristic no clasifica problemas.", "heuristic"),
    "checks": (
        "Resultados explicables de las comprobaciones.",
        CHECKS,
    ),
    "name": ("Nombre estable de la comprobación.", "category"),
    "detail": ("Explicación de la comprobación.", "no clasificado (sin modelo)"),
    "category": ("Código de categoría; consulta /api/categories.", "pothole"),
    "latitude": ("Latitud del problema en grados decimales.", 14.6349),
    "longitude": ("Longitud del problema en grados decimales.", -90.5069),
    "captured_at": ("Fecha y hora de captura con zona horaria.", AT),
    "note": (
        "Descripción pública del problema; no incluyas datos personales.",
        "Bache junto al cruce peatonal.",
    ),
    "status": (
        "Resultado de verificación (reportes), o estado abierto/cerrado (Open311).",
        "verified",
    ),
    "resolution": ("Estado de atención compatible con la versión inicial.", "open"),
    "photo_url": (
        "Ruta de la foto JPEG sin metadatos.",
        f"/api/reports/{DEMO_ID}/photo",
    ),
    "verification": (
        "Comprobaciones y modo del verificador; null si está pendiente.",
        VERIFICATION,
    ),
    "state": ("Estado de atención municipal.", "nuevo"),
    "state_group": ("Grupo del estado de atención.", "open"),
    "public_note": (
        "Mensaje oficial visible para la ciudadanía.",
        "Cuadrilla programada para el jueves.",
    ),
    "internal_note": (
        "Nota interna, visible solo para personal autorizado.",
        "Confirmar equipo disponible.",
    ),
    "actor": ("Usuario de personal que realizó el cambio, o system.", "system"),
    "bbox": (
        "Rectángulo oeste,sur,este,norte, en grados decimales.",
        "-90.52,14.62,-90.50,14.65",
    ),
    "include_old": (
        (
            "Incluye historial anterior a los últimos 30 días si no se "
            "indica fecha inicial."
        ),
        True,
    ),
    "created_from": (
        "Día inicial de creación, inclusive, en America/Guatemala.",
        "2026-09-20",
    ),
    "created_to": (
        "Día final de creación, inclusive, en America/Guatemala.",
        "2026-11-20",
    ),
    "limit": ("Número máximo de reportes por página (1–100).", 100),
    "offset": ("Número de reportes que se omiten para paginar.", 0),
    "username": ("Nombre de usuario del personal municipal.", "operador_demo"),
    "password": (
        "Contraseña privada; nunca la incluyas en registros o URLs.",
        "<contraseña privada>",
    ),
    "assignee": ("Cuadrilla asignada; null elimina la asignación.", "Cuadrilla Centro"),
    "idempotency-key": (
        (
            "UUID nuevo por reporte; reutilízalo solo al reintentar el "
            "mismo envío durante 24 horas."
        ),
        DEMO_ID,
    ),
}
ERRORS = {
    "400": ("request_error", "No se pudo procesar la solicitud."),
    "401": ("unauthorized", "Inicia sesión con un usuario y una contraseña válidos."),
    "403": ("forbidden", "Permisos insuficientes."),
    "404": ("not_found", "Recurso no encontrado."),
    "405": ("request_error", "No se pudo procesar la solicitud."),
    "409": ("invalid_transition", "Cambio de estado no permitido."),
    "413": ("upload_too_large", "La foto supera el tamaño permitido."),
    "422": ("validation_error", "Solicitud inválida."),
    "423": (
        "account_locked",
        "Cuenta bloqueada durante 15 minutos por intentos fallidos.",
    ),
    "429": ("rate_limited", "Demasiadas solicitudes. Inténtalo de nuevo más tarde."),
    "500": ("internal_error", "Error interno del servidor."),
    "503": ("staff_unavailable", "Acceso de personal no configurado."),
}
