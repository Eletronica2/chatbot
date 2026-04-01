"""JWT and password hashing helpers."""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

import jwt


def hash_password(password: str, *, iterations: int = 120000) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return "pbkdf2_sha256${}${}${}".format(
        iterations,
        base64.urlsafe_b64encode(salt).decode("utf-8"),
        base64.urlsafe_b64encode(digest).decode("utf-8"),
    )


def verify_password(password: str, encoded_hash: str) -> bool:
    try:
        algorithm, raw_iterations, raw_salt, raw_digest = encoded_hash.split("$", 3)
    except ValueError:
        return False
    if algorithm != "pbkdf2_sha256":
        return False
    iterations = int(raw_iterations)
    salt = base64.urlsafe_b64decode(raw_salt.encode("utf-8"))
    expected = base64.urlsafe_b64decode(raw_digest.encode("utf-8"))
    computed = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(expected, computed)


def create_access_token(
    payload: Dict[str, Any],
    *,
    secret_key: str,
    expires_in_minutes: int,
) -> str:
    now = datetime.now(timezone.utc)
    claims = dict(payload)
    claims["iat"] = int(now.timestamp())
    claims["exp"] = int((now + timedelta(minutes=expires_in_minutes)).timestamp())
    return jwt.encode(claims, secret_key, algorithm="HS256")


def decode_access_token(token: str, *, secret_key: str) -> Dict[str, Any]:
    return jwt.decode(token, secret_key, algorithms=["HS256"])

