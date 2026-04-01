"""Helpers for encrypting and decrypting provider credentials."""
from __future__ import annotations

import base64
import hashlib

from cryptography.fernet import Fernet


class TokenCipher:
    def __init__(self, secret_key: str):
        digest = hashlib.sha256(secret_key.encode("utf-8")).digest()
        self._fernet = Fernet(base64.urlsafe_b64encode(digest))

    def encrypt(self, raw_value: str | None) -> str | None:
        if not raw_value:
            return None
        return self._fernet.encrypt(raw_value.encode("utf-8")).decode("utf-8")

    def decrypt(self, encrypted_value: str | None) -> str | None:
        if not encrypted_value:
            return None
        return self._fernet.decrypt(encrypted_value.encode("utf-8")).decode("utf-8")

