"""Spanish operation descriptions and request/response examples."""

from app.categories import CATEGORIES, CATEGORY_GROUPS, SLA_HOURS
from app.openapi_examples import AT, DEMO_ID, EMPTY_STATS, IDENTITY, PAGE, REPORT, USER

# path, method -> tag, summary, description, successful response example.
OPERATIONS: dict[tuple[str, str], tuple[str, str, str, object]] = {
    ("/api/health", "get"): (
        "Operación",
        "Comprobar dependencias",
        (
            "Estado de la base de datos, del verificador y del directorio "
            "de fotos. No revela rutas ni errores internos."
        ),
        {
            "status": "ok",
            "dependencies": {"database": "ok", "verifier": "ok", "photos": "ok"},
        },
    ),
    ("/api/categories", "get"): (
        "Ciudadanía",
        "Consultar categorías",
        "Códigos estables, etiquetas, grupo y objetivo de atención en horas.",
        [
            {
                "id": code,
                "label": label,
                "group": CATEGORY_GROUPS[code],
                "sla_hours": SLA_HOURS[code],
            }
            for code, label in CATEGORIES
        ],
    ),
    ("/api/reports", "post"): (
        "Ciudadanía",
        "Enviar un reporte con foto",
        (
            "Foto JPEG o PNG; se elimina EXIF y se verifica antes de "
            "guardar. Si el verificador falla, el reporte queda pendiente. "
            "Idempotency-Key permite reintentos durante 24 horas (200 si ya"
            " existe, 201 si es nuevo). El modo heuristic mide calidad y "
            "metadatos; no demuestra autenticidad ni clasifica el problema."
        ),
        REPORT,
    ),
    ("/api/reports", "get"): (
        "Ciudadanía",
        "Consultar reportes",
        (
            "Lista paginada: hasta 100 por página, por defecto últimos 30 "
            "días. include_old=true incluye todo el historial; ocultos solo"
            " con sesión de personal."
        ),
        PAGE,
    ),
    ("/api/reports/{report_id}", "get"): (
        "Ciudadanía",
        "Consultar reporte y seguimiento",
        (
            "Incluye eventos públicos en orden temporal. Las notas internas"
            " solo aparecen con acceso de personal."
        ),
        REPORT,
    ),
    ("/api/reports/{report_id}/photo", "get"): (
        "Ciudadanía",
        "Ver foto sin metadatos",
        (
            "JPEG almacenado sin EXIF ni GPS. Las mismas reglas de "
            "visibilidad del reporte protegen esta imagen."
        ),
        None,
    ),
    ("/api/reports/{report_id}/thumbnail", "get"): (
        "Ciudadanía",
        "Ver miniatura de la foto",
        (
            "JPEG de hasta 320 px en el lado largo, sin EXIF ni GPS, generado "
            "a partir de la foto y guardado en caché (un día). Las mismas reglas "
            "de visibilidad del reporte protegen esta imagen."
        ),
        None,
    ),
    ("/api/reports/nearby", "get"): (
        "Ciudadanía",
        "Buscar problemas cercanos",
        (
            "Hasta 10 reportes verificados abiertos de la misma categoría, "
            "de los últimos 30 días; radio entre 20 y 500 metros."
        ),
        {"items": []},
    ),
    ("/api/reports/{report_id}/nearby", "get"): (
        "Ciudadanía",
        "Consultar posibles duplicados",
        (
            "Hasta 10 reportes cercanos a 100 metros; misma categoría, "
            "abiertos, verificados y creados en los últimos 30 días."
        ),
        {"items": []},
    ),
    ("/api/reports/clusters", "get"): (
        "Ciudadanía",
        "Consultar agrupaciones del mapa",
        (
            "Agrupa por cuadrícula según zoom; hasta 500 agrupaciones. "
            "total cuenta los reportes filtrados, incluso si se recortan "
            "las agrupaciones."
        ),
        {
            "clusters": [
                {"lat": 14.6349, "lon": -90.5069, "count": 1, "ids": [DEMO_ID]}
            ],
            "total": 1,
        },
    ),
    ("/api/stats", "get"): (
        "Indicadores",
        "Consultar indicadores municipales",
        (
            "Filtros y fechas usan días de America/Guatemala. Sin fechas, "
            "últimos 30 días. Las métricas por categoría usan la cohorte de"
            " creación; las resoluciones semanales usan la fecha de "
            "resolución. Sin muestras, las duraciones y tasas son null."
        ),
        EMPTY_STATS,
    ),
    ("/api/reports.csv", "get"): (
        "Integración",
        "Exportar reportes a CSV",
        (
            "UTF-8 con BOM, coma o punto y coma; mismos filtros que la "
            "lista, hasta 5000 filas. No incluye ocultos ni notas internas."
            " Divide la descarga por fechas si alcanza el límite."
        ),
        None,
    ),
    ("/api/open311/v2/services.json", "get"): (
        "Open311",
        "Consultar servicios Open311",
        (
            "Categorías como servicios GeoReport v2; metadata=false indica "
            "que no se requieren atributos adicionales. Esta integración es"
            " de solo lectura."
        ),
        [
            {
                "service_code": "pothole",
                "service_name": "Bache",
                "description": "Reportes de bache.",
                "metadata": False,
                "type": "realtime",
                "keywords": "pothole",
                "group": CATEGORY_GROUPS["pothole"],
            }
        ],
    ),
    ("/api/open311/v2/requests.json", "get"): (
        "Open311",
        "Consultar solicitudes Open311",
        (
            "Solo reportes verificados y visibles; hasta 1000, más "
            "recientes primero. Los filtros de fecha corresponden a "
            "creación, no a actualización. No hay cursor ni escritura "
            "Open311."
        ),
        [
            {
                "service_request_id": DEMO_ID,
                "status": "open",
                "service_code": "pothole",
                "service_name": "Bache",
                "description": "[demo] Bache junto al cruce.",
                "lat": 14.6349,
                "long": -90.5069,
                "requested_datetime": AT,
                "updated_datetime": AT,
                "media_url": f"/api/reports/{DEMO_ID}/photo",
            }
        ],
    ),
    ("/api/queue", "get"): (
        "Personal",
        "Consultar bandeja de revisión",
        (
            "Requiere sesión de personal. review muestra nuevos sin "
            "asignar; rejected muestra rechazos del verificador. Orden de "
            "verificación más antigua primero."
        ),
        {"items": [], "total": 0, "limit": 100, "offset": 0},
    ),
    ("/api/reports/{report_id}/transition", "post"): (
        "Personal",
        "Cambiar estado del reporte",
        (
            "Requiere sesión y X-CSRF-Token. Valida transiciones, motivos y"
            " permisos; conserva actor, fecha y notas en el historial. Un "
            "rechazo del verificador requiere supervisor o admin para "
            "anularlo con motivo interno."
        ),
        REPORT | {"state": "en_revision"},
    ),
    ("/api/reports/{report_id}/assign", "post"): (
        "Personal",
        "Asignar cuadrilla",
        "Requiere sesión y X-CSRF-Token. assignee=null elimina la asignación.",
        REPORT | {"assignee": "Cuadrilla Centro"},
    ),
    ("/api/auth/config", "get"): (
        "Sesiones",
        "Consultar opciones de acceso",
        "Configuración pública del acceso de personal; no incluye credenciales.",
        {"enabled": True, "dev_tokens": False},
    ),
    ("/api/auth/login", "post"): (
        "Sesiones",
        "Iniciar sesión de personal",
        (
            "Recibe credenciales por HTTPS y devuelve cookies de sesión "
            "HttpOnly y CSRF. La sesión caduca a las 12 horas; cinco fallos"
            " bloquean la cuenta 15 minutos. Nunca guardes contraseñas o "
            "cookies en URLs ni registros."
        ),
        IDENTITY,
    ),
    ("/api/auth/me", "get"): (
        "Sesiones",
        "Consultar sesión actual",
        "Requiere cookie de sesión válida; respuesta no almacenable en caché.",
        IDENTITY,
    ),
    ("/api/auth/logout", "post"): (
        "Sesiones",
        "Cerrar sesión",
        (
            "Requiere cookie y X-CSRF-Token. Revoca la sesión en SQL y "
            "elimina las cookies; devuelve 204 sin contenido."
        ),
        None,
    ),
    ("/api/admin/users", "get"): (
        "Administración",
        "Consultar usuarios de personal",
        "Solo admin; no expone hashes ni sesiones.",
        {"items": [USER]},
    ),
    ("/api/admin/users", "post"): (
        "Administración",
        "Crear usuario de personal",
        (
            "Solo admin, con sesión y X-CSRF-Token. Contraseña de 12 a 1024"
            " caracteres. Usa un canal seguro para entregarla."
        ),
        USER,
    ),
    ("/api/admin/users/{user_id}", "patch"): (
        "Administración",
        "Actualizar usuario de personal",
        (
            "Solo admin, con sesión y X-CSRF-Token. Envía al menos un campo"
            " no nulo; revoca todas las sesiones del usuario afectado."
        ),
        USER | {"disabled": True},
    ),
}
REQUEST_EXAMPLES = {
    ("/api/auth/login", "post"): {
        "username": "operador_demo",
        "password": "<contraseña privada>",
    },
    ("/api/admin/users", "post"): {
        "username": "operador_demo",
        "password": "<contraseña privada>",
        "role": "operator",
    },
    ("/api/admin/users/{user_id}", "patch"): {"disabled": True},
    ("/api/reports/{report_id}/transition", "post"): {
        "to": "en_revision",
        "public_note": "Recibimos su reporte y lo estamos revisando.",
    },
    ("/api/reports/{report_id}/assign", "post"): {"assignee": "Cuadrilla Centro"},
}
