import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.config import Settings
from app.db import Database
from app.dependencies import Services
from app.logging_config import configure_logging
from app.middleware import (
    SECURITY_HEADERS,
    SecurityMiddleware,
    UniformCORSMiddleware,
    UploadLimitMiddleware,
)
from app.openapi import install_openapi
from app.routes import auth, citizens, exports, health, open311, reports, stats, triage
from app.security import CSRF_COOKIE, SESSION_COOKIE
from app.services.storage import PhotoStorage
from app.services.verifier_client import VerifierClient

logger = logging.getLogger(__name__)


def create_app(
    settings: Settings | None = None,
    *,
    verifier_transport: httpx.BaseTransport | None = None,
) -> FastAPI:
    configure_logging()
    config = settings or Settings()
    if config.require_citizen_login and config.citizen_hash_key is None:
        raise ValueError("PHONE_HASH_KEY is required when citizen login is mandatory")
    services = Services(
        config,
        Database(config.database_url),
        PhotoStorage(config.photo_dir),
        VerifierClient(
            config.verifier_url, verifier_transport, config.verifier_timeout_seconds
        ),
    )

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        try:
            yield
        finally:
            services.verifier.close()
            services.database.engine.dispose()

    app = FastAPI(title="Aldia API", debug=False, lifespan=lifespan)
    app.state.services = services
    app.add_middleware(UploadLimitMiddleware, settings=config)
    app.add_middleware(
        UniformCORSMiddleware,
        allow_origins=config.allowed_origins,
        allow_methods=["GET", "POST", "PATCH"],
        allow_headers=[
            "Content-Type",
            "X-Staff-Token",
            "X-CSRF-Token",
            "Idempotency-Key",
            "Authorization",
            "X-Device-ID",
        ],
        allow_credentials=True,
    )
    app.add_middleware(SecurityMiddleware, settings=config)

    @app.exception_handler(RequestValidationError)
    async def invalid_request(
        _request: Request, _exc: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={
                "error": {"code": "validation_error", "message": "Solicitud inválida."}
            },
        )

    @app.exception_handler(HTTPException)
    async def http_error(_request: Request, exc: HTTPException) -> JSONResponse:
        codes = {
            401: (
                "unauthorized",
                "Inicia sesión con un usuario y una contraseña válidos.",
            ),
            403: ("forbidden", "Permisos insuficientes."),
            409: ("invalid_transition", "Cambio de estado no permitido."),
            503: ("staff_unavailable", "Acceso de personal no configurado."),
            404: ("not_found", "Recurso no encontrado."),
            413: ("upload_too_large", "La foto supera el tamaño permitido."),
            422: ("validation_error", "Solicitud inválida."),
            423: (
                "account_locked",
                "Cuenta bloqueada durante 15 minutos por intentos fallidos.",
            ),
            429: (
                "rate_limited",
                "Demasiados intentos. Espera 15 minutos e inténtalo de nuevo.",
            ),
        }
        code, message = codes.get(
            exc.status_code, ("request_error", "No se pudo procesar la solicitud.")
        )
        citizen_errors = {
            "citizen_code_invalid": (
                "El código no es válido o venció. Solicita otro e inténtalo de nuevo."
            ),
            "citizen_unauthorized": "Verifica tu número para continuar.",
            "citizen_unavailable": "La verificación de número no está disponible.",
            "idempotency_conflict": "Esta solicitud ya pertenece a otro envío.",
        }
        if isinstance(exc.detail, str) and exc.detail in citizen_errors:
            code, message = exc.detail, citizen_errors[exc.detail]
        headers = dict(exc.headers or {})
        if _request.url.path.startswith(
            ("/api/auth/", "/api/admin/", "/api/citizens/")
        ):
            headers["Cache-Control"] = "no-store"
        response = JSONResponse(
            status_code=exc.status_code,
            headers=headers,
            content={"error": {"code": code, "message": message}},
        )
        if (
            exc.status_code == 401
            and code not in {"citizen_code_invalid", "citizen_unauthorized"}
            and SESSION_COOKIE in _request.cookies
            and _request.url.path != "/api/auth/login"
        ):
            for name in (SESSION_COOKIE, CSRF_COOKIE):
                response.delete_cookie(
                    name,
                    secure=config.env != "dev",
                    httponly=name == SESSION_COOKIE,
                    samesite="lax",
                    path="/",
                )
        return response

    @app.exception_handler(Exception)
    async def internal_error(request: Request, _exc: Exception) -> JSONResponse:
        logger.error("API request failed")
        # Starlette's outer error handler sits outside the CORS middleware.
        # Add allowed-origin headers here so browsers can read the error envelope.
        origin = request.headers.get("origin")
        headers: dict[str, str] = dict(SECURITY_HEADERS)
        if origin is not None:
            if origin in config.allowed_origins:
                headers.update(
                    {"Access-Control-Allow-Origin": origin, "Vary": "Origin"}
                )
            if "Access-Control-Allow-Origin" in headers:
                headers["Access-Control-Allow-Credentials"] = "true"
        return JSONResponse(
            status_code=500,
            headers=headers,
            content={
                "error": {
                    "code": "internal_error",
                    "message": "Error interno del servidor.",
                }
            },
        )

    app.include_router(auth.router)
    app.include_router(citizens.router)
    app.include_router(health.router)
    app.include_router(stats.router)
    app.include_router(exports.router)
    app.include_router(open311.router)
    app.include_router(triage.router)
    app.include_router(reports.router)
    install_openapi(app, max_upload_bytes=config.max_upload_bytes)
    return app
