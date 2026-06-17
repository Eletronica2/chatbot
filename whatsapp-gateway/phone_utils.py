"""Normalize WhatsApp recipient numbers for Cloud API sends."""
from __future__ import annotations

import re


def normalize_whatsapp_to(value: str) -> str:
    """Convert Meta wa_id formats to API send format when needed.

    Brazilian mobiles are sometimes stored as 55 + DDD + 8 digits (without the
    leading 9). The test recipient list and outbound API require 55 + DDD + 9
    + 8 digits.
    """
    digits = re.sub(r"\D", "", value or "")
    if digits.startswith("55") and len(digits) == 12:
        ddd = digits[2:4]
        local = digits[4:]
        if len(local) == 8:
            return f"55{ddd}9{local}"
    return digits
