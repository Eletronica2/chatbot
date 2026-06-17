"""Normalize WhatsApp phone numbers for storage and outbound API calls."""
from __future__ import annotations

import re


def normalize_whatsapp_phone(value: str) -> str:
    digits = re.sub(r"\D", "", value or "")
    if digits.startswith("55") and len(digits) == 12:
        ddd = digits[2:4]
        local = digits[4:]
        if len(local) == 8:
            return f"55{ddd}9{local}"
    return digits
