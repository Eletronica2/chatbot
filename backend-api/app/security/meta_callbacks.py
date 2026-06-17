"""Helpers for Meta platform callbacks (data deletion, signed requests)."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
from typing import Any


def parse_signed_request(signed_request: str, app_secret: str) -> dict[str, Any] | None:
    if not signed_request or "." not in signed_request:
        return None
    encoded_sig, payload = signed_request.split(".", 1)
    try:
        sig = base64.urlsafe_b64decode(_pad_base64(encoded_sig))
        data = json.loads(base64.urlsafe_b64decode(_pad_base64(payload)).decode("utf-8"))
    except (ValueError, json.JSONDecodeError):
        return None
    expected = hmac.new(
        app_secret.encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    if not hmac.compare_digest(sig, expected):
        return None
    return data


def _pad_base64(value: str) -> str:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return value + padding


def new_confirmation_code() -> str:
    return secrets.token_urlsafe(12)
