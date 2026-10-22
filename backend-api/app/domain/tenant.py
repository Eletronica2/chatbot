"""Domain models for tenant-level runtime settings."""
from __future__ import annotations

from typing import Dict, List

from pydantic import BaseModel, Field


DEFAULT_GEMINI_MODEL = "gemini-1.5-flash-latest"

DEFAULT_GEMINI_FALLBACK_MODELS: List[str] = [
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
    "gemini-1.0-pro",
    "gemini-pro",
    "gemini-1.5-pro",
    "gemini-2.0-pro",
    "gemini-2.0-flash-lite",
    "gemini-1.5-flash-latest",
    "gemini-1.5-pro-latest",
]


def normalize_model_list(models: List[str] | None) -> List[str]:
    if not models:
        return []

    normalized: List[str] = []
    for raw in models:
        if not isinstance(raw, str):
            continue
        item = raw.strip()
        if item.startswith("models/"):
            item = item.split("models/", 1)[1]
        if item and item not in normalized:
            normalized.append(item)
    return normalized


AUTO_REPLY_MODES = ("on", "off", "allowlist")


def normalize_sender(value: object) -> str:
    """Canonical E.164 digits. Brazilian mobiles may arrive from Meta without the ninth digit
    (55 + DDD + 8 digits); both forms map to 55 + DDD + 9 + 8 digits so they compare equal."""
    digits = "".join(ch for ch in str(value or "") if ch.isdigit())
    if len(digits) == 12 and digits.startswith("55") and digits[4] in "6789":
        return f"{digits[:4]}9{digits[4:]}"
    return digits


class TenantSettings(BaseModel):
    tenant_id: str
    tenant_name: str = "Tenant"
    ai_enabled: bool = True
    ai_provider: str = "gemini"
    local_ai_enabled: bool = False
    # "on": automatic replies for every sender (default, unchanged behavior);
    # "off": inbound is stored and handed to a human, nothing is sent automatically;
    # "allowlist": automatic replies only for the listed E.164 senders.
    auto_reply_mode: str = "on"
    auto_reply_allowlist: List[str] = Field(default_factory=list)
    flow_editing_enabled: bool = True
    debug_mode: bool = False
    gemini_model: str = DEFAULT_GEMINI_MODEL
    fallback_models: List[str] = Field(
        default_factory=lambda: list(DEFAULT_GEMINI_FALLBACK_MODELS)
    )
    available_models: List[str] = Field(
        default_factory=lambda: list(DEFAULT_GEMINI_FALLBACK_MODELS)
    )

    def auto_reply_block_reason(self, sender: object) -> str | None:
        """None when an automatic reply may be sent to this sender; otherwise the reason it may not."""
        mode = self.auto_reply_mode if self.auto_reply_mode in AUTO_REPLY_MODES else "off"
        if mode == "on":
            return None
        if mode == "allowlist":
            normalized = normalize_sender(sender)
            if normalized and normalized in {normalize_sender(item) for item in self.auto_reply_allowlist}:
                return None
            return "auto_reply_sender_not_allowed"
        return "auto_reply_disabled"

    def as_ai_metadata(self) -> Dict[str, object]:
        metadata: Dict[str, object] = {
            "ai_model": self.gemini_model,
            "ai_fallback_models": list(self.fallback_models),
            "tenant_id": self.tenant_id,
            "debug_mode": self.debug_mode,
            # Explicitly overwrite caller supplied metadata to prevent provider spoofing.
            "ai_provider": self.ai_provider if self.ai_provider == "local" and self.local_ai_enabled else "gemini",
        }
        return metadata

