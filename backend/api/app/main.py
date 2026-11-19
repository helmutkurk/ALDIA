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
from app.middleware import UniformCORSMiddleware, UploadLimitMiddleware
from app.routes import exports, health, open311, reports, stats
from app.services.storage import PhotoStorage
from app.services.verifier_client import VerifierClient

logger = logging.getLogger(__name__)


def create_app(
    settings: Settings | None = None,
    *,
    verifier_transport: httpx.BaseTransport | None = None,
) -> FastAPI:
    config = settings or Settings()
    services = Services(
        config,
        Database(config.database_url),
        PhotoStorage(config.photo_dir),
        VerifierClient(config.verifier_url, verifier_transport),
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
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
    )

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
            404: ("not_found", "Recurso no encontrado."),
            413: ("upload_too_large", "La foto supera el tamaño permitido."),
            422: ("validation_error", "Solicitud inválida."),
        }
        code, message = codes.get(
            exc.status_code, ("request_error", "No se pudo procesar la solicitud.")
        )
        return JSONResponse(
            status_code=exc.status_code,
            headers=exc.headers,
            content={"error": {"code": code, "message": message}},
        )

    @app.exception_handler(Exception)
    async def internal_error(request: Request, _exc: Exception) -> JSONResponse:
        logger.error("API request failed")
        # Starlette's outer error handler sits outside the CORS middleware.
        # Add allowed-origin headers here so browsers can read the error envelope.
        origin = request.headers.get("origin")
        headers: dict[str, str] = {}
        if origin is not None:
            if "*" in config.allowed_origins:
                headers["Access-Control-Allow-Origin"] = "*"
            elif origin in config.allowed_origins:
                headers = {"Access-Control-Allow-Origin": origin, "Vary": "Origin"}
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

    app.include_router(health.router)
    app.include_router(stats.router)
    app.include_router(exports.router)
    app.include_router(open311.router)
    app.include_router(reports.router)
    return app
