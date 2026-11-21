"""Install OpenAPI presentation metadata without changing runtime contracts."""

from copy import deepcopy
from typing import cast

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

from app.openapi_examples import AT
from app.openapi_fields import ERRORS, FIELD_DOCS
from app.openapi_operations import OPERATIONS, REQUEST_EXAMPLES
from app.openapi_types import Component, Document
from app.schemas import ErrorResponse, ReportCreate


def install_openapi(app: FastAPI, *, max_upload_bytes: int) -> None:
    """Install docs only; never changes route validation or response data."""

    def openapi() -> dict[str, object]:
        if app.openapi_schema is not None:
            return app.openapi_schema
        schema = cast(
            Document,
            get_openapi(
                title=app.title,
                version="0.4.0",
                description=(
                    "Reportes ciudadanos y atención municipal de Aldia. Todos los "
                    "ejemplos son sintéticos. Fechas ISO 8601 con zona horaria; "
                    "errores con envoltura uniforme. Integración Open311 de solo "
                    "lectura."
                ),
                routes=app.routes,
            ),
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
        components.update(cast(dict[str, Component], error_schema.pop("$defs", {})))
        components["ErrorResponse"] = cast(Component, error_schema)
        components.pop("HTTPValidationError", None)
        components.pop("ValidationError", None)
        components["ReportCreate"] = cast(Component, ReportCreate.model_json_schema())
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
            operation.update(
                {"tags": [tag], "summary": summary, "description": description}
            )
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
        schema["paths"]["/api/reports/{report_id}/thumbnail"]["get"]["responses"][
            "200"
        ]["content"] = {
            "image/jpeg": {
                "schema": {"type": "string", "format": "binary"},
                "example": "(bytes JPEG miniatura sin EXIF)",
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
        result = cast(dict[str, object], schema)
        app.openapi_schema = result
        return result

    app.openapi = openapi  # type: ignore[method-assign]
