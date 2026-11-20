"""Allowlisted JSON application logs; never serialize requests or exceptions."""

import json
import logging
from datetime import UTC, datetime


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "time": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "event": record.getMessage(),
        }
        fields = getattr(record, "request_fields", {})
        for name in ("method", "route", "status", "duration_ms"):
            if name in fields:
                payload[name] = fields[name]
        return json.dumps(payload, ensure_ascii=False)


def configure_logging() -> None:
    logger = logging.getLogger("app")
    if not any(
        isinstance(handler.formatter, JsonFormatter) for handler in logger.handlers
    ):
        handler = logging.StreamHandler()
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
    logger.setLevel(logging.INFO)
