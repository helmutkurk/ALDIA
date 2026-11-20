import logging
import math
import time
from collections import deque
from threading import Lock

from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from starlette.datastructures import Headers
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.config import Settings

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}


class PublicPostLimiter:
    """Bounded sliding window, direct peer IP only, local to one process."""

    def __init__(self, settings: Settings) -> None:
        self.limit = settings.public_post_rate_limit
        self.window = settings.public_post_window_seconds
        self.buckets: dict[str, deque[float]] = {}
        self.lock = Lock()

    def retry_after(self, peer: str) -> int:
        now = time.monotonic()
        with self.lock:
            # Bound retained IPs as well as request counts; fail closed if full.
            for key in list(self.buckets):
                if self.buckets[key][-1] <= now - self.window:
                    del self.buckets[key]
            if peer not in self.buckets and len(self.buckets) >= 10000:
                return self.window
            bucket = self.buckets.setdefault(peer, deque())
            while bucket and bucket[0] <= now - self.window:
                bucket.popleft()
            if len(bucket) >= self.limit:
                return max(1, math.ceil(bucket[0] + self.window - now))
            bucket.append(now)
            return 0


class SecurityMiddleware:
    """Security headers, public-write throttling and privacy-safe request logs."""

    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self.limiter = PublicPostLimiter(settings)
        self.allowed_origins = settings.allowed_origins

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = time.monotonic()
        status = 500

        async def secured_send(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
                blocked = {b"server", b"x-powered-by"} | {
                    name.lower().encode() for name in SECURITY_HEADERS
                }
                message["headers"] = [
                    (key, value)
                    for key, value in message.get("headers", [])
                    if key.lower() not in blocked
                ] + [
                    (key.lower().encode(), value.encode())
                    for key, value in SECURITY_HEADERS.items()
                ]
            await send(message)

        try:
            if scope["method"] == "POST" and scope["path"].rstrip("/") in {
                "/api/reports",
                "/api/auth/login",
            }:
                peer = scope.get("client")
                retry = self.limiter.retry_after(peer[0] if peer else "unknown")
                if retry:
                    headers = {"Retry-After": str(retry), "Cache-Control": "no-store"}
                    origin = Headers(scope=scope).get("origin")
                    if origin in self.allowed_origins:
                        headers.update(
                            {
                                "Access-Control-Allow-Origin": origin,
                                "Access-Control-Allow-Credentials": "true",
                                "Vary": "Origin",
                            }
                        )
                    response = JSONResponse(
                        status_code=429,
                        headers=headers,
                        content={
                            "error": {
                                "code": "rate_limited",
                                "message": "Demasiadas solicitudes. Espera un momento.",
                            }
                        },
                    )
                    await response(scope, receive, secured_send)
                    return
            await self.app(scope, receive, secured_send)
        finally:
            route = scope.get("route")
            logging.getLogger("app.requests").info(
                "http_request",
                extra={
                    "request_fields": {
                        "method": scope["method"],
                        "route": getattr(route, "path", "unmatched"),
                        "status": status,
                        "duration_ms": round((time.monotonic() - started) * 1000, 2),
                    }
                },
            )


class UploadLimitMiddleware:
    """Bound the entire multipart body before Starlette spools uploaded files."""

    def __init__(self, app: ASGIApp, settings: Settings) -> None:
        self.app = app
        self.settings = settings

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] not in {"POST", "PUT", "PATCH"}:
            await self.app(scope, receive, send)
            return
        # Allow room for bounded multipart fields/headers; photo size is checked
        # separately in the route. Count bytes even for chunked requests.
        maximum = (
            self.settings.max_upload_bytes + 65536
            if scope["method"] == "POST" and scope["path"].rstrip("/") == "/api/reports"
            else self.settings.max_request_bytes
        )
        chunks: list[bytes] = []
        total = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            total += len(chunk)
            if total > maximum:
                response = JSONResponse(
                    status_code=413,
                    content={
                        "error": {
                            "code": "upload_too_large",
                            "message": "La foto supera el tamaño permitido.",
                        }
                    },
                )
                await response(scope, receive, send)
                return
            chunks.append(chunk)
            if not message.get("more_body", False):
                break
        sent = False

        async def replay() -> Message:
            nonlocal sent
            if sent:
                return await receive()
            sent = True
            return {
                "type": "http.request",
                "body": b"".join(chunks),
                "more_body": False,
            }

        await self.app(scope, replay, send)


class UniformCORSMiddleware(CORSMiddleware):
    def preflight_response(self, request_headers: Headers) -> Response:
        response = super().preflight_response(request_headers)
        if response.status_code < 400:
            return response
        headers = {
            key: value
            for key, value in response.headers.items()
            if key not in {"content-length", "content-type"}
        }
        return JSONResponse(
            status_code=response.status_code,
            content={
                "error": {
                    "code": "cors_error",
                    "message": "Origen o método no permitido.",
                }
            },
            headers=headers,
        )
