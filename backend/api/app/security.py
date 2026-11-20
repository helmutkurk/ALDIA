"""Password and opaque-session primitives; credentials must never be logged."""

import hashlib
import hmac
import re
import secrets
import time
from collections import OrderedDict, deque
from threading import Lock
from typing import Literal

from argon2 import PasswordHasher, Type
from argon2.exceptions import VerificationError

StaffRole = Literal["operator", "supervisor", "admin"]

PASSWORD_HASHER = PasswordHasher(
    time_cost=3,
    memory_cost=65536,
    parallelism=4,
    hash_len=32,
    salt_len=16,
    type=Type.ID,
)
# Unknown users still pay the same Argon2 verification cost.
_DUMMY_HASH = PASSWORD_HASHER.hash(secrets.token_urlsafe(32))
SESSION_COOKIE = "aldia_session"
CSRF_COOKIE = "aldia_csrf"
SESSION_SECONDS = 12 * 60 * 60
USERNAME_PATTERN = r"[a-z0-9_][a-z0-9_.-]{2,63}"


def valid_username(value: str) -> bool:
    return re.fullmatch(USERNAME_PATTERN, value) is not None


def hash_password(password: str) -> str:
    if not 12 <= len(password) <= 1024:
        raise ValueError("Password must contain 12–1024 characters")
    return PASSWORD_HASHER.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        verified = PASSWORD_HASHER.verify(password_hash or _DUMMY_HASH, password)
        return verified and password_hash is not None
    except VerificationError:
        return False


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def constant_equal(left: str, right: str) -> bool:
    return hmac.compare_digest(left.encode("utf-8"), right.encode("utf-8"))


def signature(raw_id: str, signing_key: str) -> str:
    return hmac.new(signing_key.encode(), raw_id.encode(), hashlib.sha256).hexdigest()


class LoginLimiter:
    """Bounded per-process sliding window, keyed by normalized username + peer IP."""

    def __init__(self) -> None:
        self.attempts: OrderedDict[tuple[str, str], deque[float]] = OrderedDict()
        self.lock = Lock()

    def allow(self, username: str, ip: str) -> bool:
        now = time.monotonic()
        with self.lock:
            key = (username, ip)
            bucket = self.attempts.setdefault(key, deque())
            self.attempts.move_to_end(key)
            while bucket and bucket[0] <= now - 900:
                bucket.popleft()
            allowed = len(bucket) < 10
            if allowed:
                bucket.append(now)
            while len(self.attempts) > 10000:
                self.attempts.popitem(last=False)
            return allowed
