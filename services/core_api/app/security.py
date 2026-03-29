import base64
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone

import jwt

from app.config import settings

_ALGORITHM = "sha256"
_ITERATIONS = 390_000


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac(_ALGORITHM, password.encode("utf-8"), salt, _ITERATIONS)
    salt_b64 = base64.urlsafe_b64encode(salt).decode("ascii")
    digest_b64 = base64.urlsafe_b64encode(digest).decode("ascii")
    return f"pbkdf2_{_ALGORITHM}${_ITERATIONS}${salt_b64}${digest_b64}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        method, iterations, salt_b64, digest_b64 = password_hash.split("$", 3)
    except ValueError:
        return False

    if method != f"pbkdf2_{_ALGORITHM}":
        return False

    salt = base64.urlsafe_b64decode(salt_b64.encode("ascii"))
    expected_digest = base64.urlsafe_b64decode(digest_b64.encode("ascii"))
    candidate = hashlib.pbkdf2_hmac(
        _ALGORITHM,
        password.encode("utf-8"),
        salt,
        int(iterations),
    )
    return hmac.compare_digest(candidate, expected_digest)


def create_token(payload: dict, expires_minutes: int) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=expires_minutes)
    signed_payload = {**payload, "exp": expires_at}
    return jwt.encode(signed_payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_access_token(subject: str) -> str:
    payload = {"sub": subject, "kind": "access"}
    return create_token(payload, settings.access_token_minutes)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
