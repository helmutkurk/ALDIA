"""No network delivery. Console output is deliberately restricted to development."""

import logging
from typing import Protocol

from app.config import Settings


class SmsUnavailable(Exception):
    pass


class SmsProvider(Protocol):
    def send_code(self, phone: str, code: str) -> None: ...


class NullSmsProvider:
    def send_code(self, phone: str, code: str) -> None:
        raise SmsUnavailable("Citizen delivery is not configured")


class ConsoleSmsProvider:
    def __init__(self, settings: Settings) -> None:
        if settings.env != "dev":
            raise ValueError("Console SMS is available only with ENV=dev")
        self.settings = settings

    def send_code(self, phone: str, code: str) -> None:
        if self.settings.env != "dev":
            raise SmsUnavailable("Console SMS is available only with ENV=dev")
        # Explicit developer-only exception. Never log the destination number.
        logging.getLogger("app.citizen_dev").warning(
            "!!! DEV ONLY — NO SMS SENT — CITIZEN OTP: %s !!!", code
        )


def sms_provider(settings: Settings) -> SmsProvider:
    if settings.citizen_sms_provider == "console":
        return ConsoleSmsProvider(settings)
    return NullSmsProvider()
