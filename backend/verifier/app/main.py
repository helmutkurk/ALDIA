import logging
from datetime import datetime

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool
from starlette.datastructures import UploadFile
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.checks import Classifier, StubClassifier, VerifyInput, VerifyResult, verify
from app.config import Settings
from app.middleware import UploadLimitMiddleware

logger = logging.getLogger(__name__)
# Internal requests still have a fixed safety cap; the API's public default is 8 MiB.
MAX_IMAGE_BYTES = 32 * 1024 * 1024


def error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status, content={"error": {"code": code, "message": message}}
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    config = settings or Settings()
    if config.verifier_mode == "model":
        raise NotImplementedError(
            "VERIFIER_MODE=model requires a trained model: "
            "implement Classifier.classify "
            "and load the classifier in app/main.py; see training/README.md."
        )
    classifier: Classifier = StubClassifier()
    app = FastAPI(title="Aldia verifier", debug=False)
    app.add_middleware(UploadLimitMiddleware, max_upload_bytes=MAX_IMAGE_BYTES)

    @app.exception_handler(RequestValidationError)
    async def validation_error(
        _request: Request, _exc: RequestValidationError
    ) -> JSONResponse:
        return error(422, "validation_error", "Solicitud inválida.")

    @app.exception_handler(StarletteHTTPException)
    async def http_error(
        _request: Request, exc: StarletteHTTPException
    ) -> JSONResponse:
        response = error(exc.status_code, "request_error", "Solicitud inválida.")
        if exc.headers:
            response.headers.update(exc.headers)
        return response

    @app.exception_handler(Exception)
    async def unexpected_error(_request: Request, _exc: Exception) -> JSONResponse:
        logger.error("Verifier request failed")
        return error(500, "internal_error", "Error interno del servidor.")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok", "mode": "heuristic"}

    @app.post("/verify", response_model=VerifyResult)
    async def verify_photo(request: Request) -> VerifyResult:
        async with request.form(max_files=2, max_fields=16, max_part_size=4096) as form:
            if len(form.multi_items()) != len(form):
                raise HTTPException(422)
            upload = form.get("photo")
            if not isinstance(upload, UploadFile):
                raise HTTPException(422)
            values = {key: value for key, value in form.items() if key != "photo"}
            if any(not isinstance(value, str) for value in values.values()):
                raise HTTPException(422)
            try:
                # Parse multipart text before strict validation.
                parsed: dict[str, object] = dict(values)
                for key in ("latitude", "longitude"):
                    if key in parsed:
                        parsed[key] = float(str(parsed[key]))
                if "captured_at" in parsed:
                    parsed["captured_at"] = datetime.fromisoformat(
                        str(parsed["captured_at"])
                    )
                report = VerifyInput.model_validate(parsed)
            except (ValueError, ValidationError) as exc:
                raise HTTPException(422) from exc
            data = await upload.read(MAX_IMAGE_BYTES + 1)
            if len(data) > MAX_IMAGE_BYTES:
                raise HTTPException(413)
            try:
                return await run_in_threadpool(
                    verify,
                    data,
                    report,
                    classifier,
                    config,
                )
            except ValueError as exc:
                raise HTTPException(422) from exc

    return app
