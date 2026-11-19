.PHONY: install dev test lint fmt migrate

install:
	uv sync --frozen

dev:
	uv run uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8001 --reload --no-access-log

test:
	uv run pytest

lint:
	uv run ruff check
	uv run ruff format --check
	uv run mypy app

fmt:
	uv run ruff format
	uv run ruff check --fix

migrate:
	@echo "The verifier has no database migrations."
