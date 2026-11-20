FROM ghcr.io/astral-sh/uv:0.12.23 AS uv

FROM python:3.12.15-slim AS builder
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /service
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

FROM python:3.12.15-slim AS runtime
COPY --from=uv /uv /usr/local/bin/uv
ENV PATH="/service/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    UV_CACHE_DIR=/tmp/uv-cache UV_PYTHON_DOWNLOADS=never
RUN groupadd --gid 10001 aldia \
    && useradd --uid 10001 --gid aldia --create-home aldia \
    && mkdir -p /data/photos \
    && chown -R aldia:aldia /data \
    && chmod 700 /data/photos
WORKDIR /service
COPY --from=builder /service/.venv ./.venv
COPY pyproject.toml uv.lock ./
COPY app ./app
COPY alembic ./alembic
COPY alembic.ini ./alembic.ini
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=8s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=7)"]
CMD ["uv", "run", "--no-sync", "uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--no-access-log", "--no-server-header", "--no-proxy-headers"]
