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


class TenantSettings(BaseModel):
    tenant_id: str
    tenant_name: str = "Tenant"
    ai_enabled: bool = True
    flow_editing_enabled: bool = True
    debug_mode: bool = False
    gemini_model: str = DEFAULT_GEMINI_MODEL
    fallback_models: List[str] = Field(
        default_factory=lambda: list(DEFAULT_GEMINI_FALLBACK_MODELS)
    )
    available_models: List[str] = Field(
        default_factory=lambda: list(DEFAULT_GEMINI_FALLBACK_MODELS)
    )

    def as_ai_metadata(self) -> Dict[str, object]:
        return {
            "ai_model": self.gemini_model,
            "ai_fallback_models": list(self.fallback_models),
            "tenant_id": self.tenant_id,
            "debug_mode": self.debug_mode,
        }

