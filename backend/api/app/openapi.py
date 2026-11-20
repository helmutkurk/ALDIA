"""OpenAPI presentation metadata, kept separate from request handling."""

from copy import deepcopy
from typing import Any

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

from app.categories import CATEGORIES, CATEGORY_GROUPS, SLA_HOURS
from app.schemas import ErrorResponse, ReportCreate

DEMO_ID = "8d231ed0-b858-4bd5-bf2e-c8c5a4d2dd01"
AT = "2026-11-20T12:00:00Z"
REPORT: dict[str, Any] = {
    "id": DEMO_ID,
    "category": "pothole",
    "latitude": 14.6349,
    "longitude": -90.5069,
    "captured_at": AT,
    "created_at": AT,
    "status": "verified",
    "resolution": "open",
    "note": "[demo] Bache junto al cruce peatonal.",
    "photo_url": f"/api/reports/{DEMO_ID}/photo",
    "verification": {
        "passed": True,
        "mode": "heuristic",
        "checks": [
            {
                "name": "image",
                "passed": True,
                "detail": "800x600 jpeg",
                "code": "image_ok",
            },
            {
                "name": "place",
                "passed": True,
                "detail": "Dentro de Guatemala.",
                "code": "place_ok",
            },
            {
                "name": "freshness",
                "passed": True,
                "detail": "Captura reciente.",
                "code": "freshness_ok",
            },
            {
                "name": "category",
                "passed": True,
                "detail": "no clasificado (sin modelo)",
                "code": "category_stub",
            },
            {"name": "duplicate", "passed": True, "detail": "no nearby duplicate"},
        ],
    },
    "state": "nuevo",
    "state_group": "open",
    "state_changed_at": AT,
    "verified_at": AT,
    "resolved_at": None,
    "closed_at": None,
    "assignee": None,
    "assigned_at": None,
    "duplicate_of": None,
    "public_note": None,
    "events": [
        {
            "at": AT,
            "actor": "system",
            "actor_role": "system",
            "from_state": "pendiente_verificacion",
            "to_state": "nuevo",
            "public_note": None,
        }
    ],
}
PAGE = {"items": [REPORT], "total": 1, "limit": 100, "offset": 0}
USER = {
    "id": DEMO_ID,
    "username": "operador_demo",
    "role": "operator",
    "disabled": False,
}
IDENTITY = {"user": {"username": "operador_demo", "role": "operator"}}
CATEGORY_ROWS = [
    {
        "category": code,
        "total": 0,
        "resueltos": 0,
        "abiertos": 0,
        "cerrados": 0,
        "mediana_reparacion_horas": None,
        "p90_reparacion_horas": None,
        "n_resueltos": 0,
    }
    for code, _ in CATEGORIES
]
EMPTY_STATS = {
    "total": 0,
    "by_category": {code: 0 for code, _ in CATEGORIES},
    "by_status": {"pending": 0, "verified": 0, "rejected": 0},
    "by_resolution": {"open": 0, "acknowledged": 0, "fixed": 0, "closed": 0},
    "recibidos": 0,
    "rechazados_verificador": 0,
    "abiertos": 0,
    "resueltos": 0,
    "cerrados_sin_solucion": 0,
    "tasa_resolucion": None,
    "tasa_resolucion_n": 0,
    "resolucion_horas": {"median": None, "p90": None, "mean": None, "n": 0},
    "primera_respuesta_horas": {"median": None, "p90": None, "n": 0},
    "antiguedad_abiertos": {"0-2": 0, "3-7": 0, "8-30": 0, ">30": 0},
    "sla_cumplido": None,
    "vencidos": 0,
    "by_state": {},
    "by_state_group": {},
    "weekly": [],
    "por_categoria": CATEGORY_ROWS,
    "top_categorias": [],
}

# path, method -> tag, summary, description, successful response example.
OPERATIONS: dict[tuple[str, str], tuple[str, str, str, Any]] = {
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
FIELD_DOCS: dict[str, tuple[str, Any]] = {
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
        REPORT["events"],
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
        REPORT["verification"]["checks"],
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
        REPORT["verification"],
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


def install_openapi(app: FastAPI, *, max_upload_bytes: int) -> None:
    """Install docs only; never changes route validation or response data."""

    def openapi() -> dict[str, Any]:
        if app.openapi_schema is not None:
            return app.openapi_schema
        schema = get_openapi(
            title=app.title,
            version="0.4.0",
            description=(
                "Reportes ciudadanos y atención municipal de Aldia. Todos los "
                "ejemplos son sintéticos. Fechas ISO 8601 con zona horaria; "
                "errores con envoltura uniforme. Integración Open311 de solo "
                "lectura."
            ),
            routes=app.routes,
        )
        common = schema.setdefault("components", {})
        common["securitySchemes"] = {
            "StaffSession": {
                "type": "apiKey",
                "in": "cookie",
                "name": "aldia_session",
                "description": "Sesión de personal obtenida por /api/auth/login.",
            }
        }
        components = common.setdefault("schemas", {})
        error_schema = ErrorResponse.model_json_schema(
            ref_template="#/components/schemas/{model}"
        )
        components.update(error_schema.pop("$defs", {}))
        components["ErrorResponse"] = error_schema
        components.pop("HTTPValidationError", None)
        components.pop("ValidationError", None)
        components["ReportCreate"] = ReportCreate.model_json_schema()
        for component in components.values():
            for name, field in component.get("properties", {}).items():
                if name in FIELD_DOCS:
                    description, example = FIELD_DOCS[name]
                    field.setdefault("description", description)
                    # Enum examples must match the specific schema (Open311 differs).
                    allowed = field.get("enum")
                    if not allowed or example in allowed:
                        field.setdefault("examples", [example])
        tags = sorted({entry[0] for entry in OPERATIONS.values()})
        schema["tags"] = [
            {"name": tag, "description": f"Operaciones de {tag.lower()}."}
            for tag in tags
        ]
        for (path, method), (tag, summary, description, example) in OPERATIONS.items():
            operation = schema["paths"].get(path, {}).get(method)
            if operation is None:
                continue
            operation.update(tags=[tag], summary=summary, description=description)
            for parameter in operation.get("parameters", []):
                docs = FIELD_DOCS.get(parameter["name"].lower())
                if docs:
                    parameter["description"], parameter["example"] = docs
            responses = operation["responses"]
            for status, response in responses.items():
                if status.startswith("2"):
                    response["description"] = (
                        "Solicitud completada."
                        if status != "204"
                        else "Sesión cerrada; sin contenido."
                    )
                    if example is not None:
                        response.setdefault("content", {}).setdefault(
                            "application/json", {}
                        )["example"] = deepcopy(example)
            statuses = {"500"}
            if operation.get("parameters") or operation.get("requestBody"):
                statuses.add("422")
            staff = tag in {"Personal", "Administración"} or path in {
                "/api/auth/me",
                "/api/auth/logout",
            }
            if staff:
                operation["security"] = [{"StaffSession": []}]
                statuses.update({"401", "403"})
                if method in {"post", "patch"}:
                    operation.setdefault("parameters", []).append(
                        {
                            "name": "X-CSRF-Token",
                            "in": "header",
                            "required": True,
                            "description": "Copia la cookie aldia_csrf.",
                            "schema": {"type": "string"},
                            "example": "<valor de la cookie CSRF>",
                        }
                    )
            if "{report_id}" in path or "{user_id}" in path:
                statuses.add("404")
            if method in {"post", "patch"}:
                statuses.update({"413", "422"})
            if (path, method) in {
                ("/api/reports", "post"),
                ("/api/auth/login", "post"),
            }:
                statuses.update({"400", "429"})
            if path == "/api/auth/login":
                statuses.update({"401", "403", "423"})
            if path.endswith("/transition") or (
                path == "/api/admin/users" and method == "post"
            ):
                statuses.add("409")
            for status in sorted(statuses):
                code, message = ERRORS[status]
                responses[status] = {
                    "description": message,
                    "content": {
                        "application/json": {
                            "schema": {"$ref": "#/components/schemas/ErrorResponse"},
                            "example": {"error": {"code": code, "message": message}},
                        }
                    },
                }
                if status == "429":
                    responses[status]["headers"] = {
                        "Retry-After": {
                            "description": "Espera indicada, en segundos.",
                            "schema": {"type": "integer"},
                            "example": 60,
                        }
                    }
            responses["default"] = {
                "description": "Error con código estable y mensaje en español.",
                "content": {
                    "application/json": {
                        "schema": {"$ref": "#/components/schemas/ErrorResponse"},
                        "example": {
                            "error": {
                                "code": "request_error",
                                "message": "No se pudo procesar la solicitud.",
                            }
                        },
                    }
                },
            }
            if (path, method) in REQUEST_EXAMPLES:
                operation["requestBody"]["content"]["application/json"]["example"] = (
                    REQUEST_EXAMPLES[path, method]
                )
        health = schema["paths"]["/api/health"]["get"]
        health_schema = {
            "type": "object",
            "required": ["status", "dependencies"],
            "properties": {
                "status": {"type": "string", "enum": ["ok", "degraded"]},
                "dependencies": {
                    "type": "object",
                    "required": ["database", "verifier", "photos"],
                    "properties": {
                        name: {"type": "string", "enum": ["ok", "unavailable"]}
                        for name in ("database", "verifier", "photos")
                    },
                },
            },
        }
        health["responses"]["200"]["content"]["application/json"]["schema"] = (
            health_schema
        )
        health["responses"]["503"] = {
            "description": "Una o más dependencias no están disponibles.",
            "content": {
                "application/json": {
                    "schema": health_schema,
                    "example": {
                        "status": "degraded",
                        "dependencies": {
                            "database": "ok",
                            "verifier": "unavailable",
                            "photos": "ok",
                        },
                    },
                }
            },
        }
        upload = schema["paths"]["/api/reports"]["post"]
        upload["requestBody"] = {
            "required": True,
            "content": {
                "multipart/form-data": {
                    "schema": {
                        "type": "object",
                        "additionalProperties": False,
                        "required": [
                            "photo",
                            "category",
                            "latitude",
                            "longitude",
                            "captured_at",
                        ],
                        "properties": {
                            "photo": {
                                "type": "string",
                                "format": "binary",
                                "description": (
                                    f"JPEG o PNG, máximo {max_upload_bytes} bytes; "
                                    "sin personas ni matrículas."
                                ),
                            },
                            **deepcopy(components["ReportCreate"]["properties"]),
                        },
                    },
                    "example": {
                        "photo": "(archivo JPEG sintético)",
                        "category": "pothole",
                        "latitude": 14.6349,
                        "longitude": -90.5069,
                        "captured_at": AT,
                        "note": "[demo] Bache junto al cruce.",
                    },
                }
            },
        }
        upload["responses"]["200"] = deepcopy(upload["responses"]["201"])
        upload["responses"]["200"]["description"] = (
            "Reintento idempotente; devuelve el reporte original sin crear otro."
        )
        schema["paths"]["/api/reports/{report_id}/photo"]["get"]["responses"]["200"][
            "content"
        ] = {
            "image/jpeg": {
                "schema": {"type": "string", "format": "binary"},
                "example": "(bytes JPEG sin EXIF)",
            }
        }
        schema["paths"]["/api/reports.csv"]["get"]["responses"]["200"]["content"] = {
            "text/csv": {
                "schema": {"type": "string"},
                "example": (
                    "\ufeffid,created_at,verified_at,category,state,state_changed_at,res"
                    "olved_at,latitude,longitude,assignee,verifier_status,duplicate"
                    "s_count,days_open,link\r\n"
                ),
            }
        }
        app.openapi_schema = schema
        return schema

    app.openapi = openapi  # type: ignore[method-assign]
